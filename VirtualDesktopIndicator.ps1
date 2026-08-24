<#
.SYNOPSIS
    Windows 11 virtual desktop name overlay and system-tray indicator.

.DESCRIPTION
    Reads the current virtual desktop name from the VirtualDesktop
    (PSVirtualDesktop) module and displays it in a click-through, topmost overlay
    at the upper-right corner of the primary screen. The tray menu can show or
    hide the overlay and exit the indicator.

.REQUIREMENTS
    Windows 11, Windows PowerShell 5.1 or PowerShell 7+, and the VirtualDesktop
    module from PSVirtualDesktop.

    Install the module for the current user (no administrator required):
        Install-Module -Name VirtualDesktop -Scope CurrentUser

.EXAMPLE
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "C:\Tools\VirtualDesktopIndicator.ps1"

.NOTES
    For a quiet startup, add -WindowStyle Hidden to the example command.
    The overlay works above ordinary and borderless-fullscreen windows. A true
    exclusive-fullscreen DirectX application can bypass the Windows compositor
    and may cover any normal desktop overlay.
#>

[CmdletBinding()]
param(
    [ValidateRange(200, 5000)]
    [int]$PollIntervalMilliseconds = 500,

    [ValidateRange(0, 200)]
    [int]$OverlayMargin = 16,

    [switch]$StartHidden
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:OverlayWindow = $null
$script:OverlayText = $null
$script:OverlayHwnd = [IntPtr]::Zero
$script:TrayIcon = $null
$script:TrayMenu = $null
$script:ToggleOverlayMenuItem = $null
$script:PollTimer = $null
$script:Dispatcher = $null
$script:InstanceMutex = $null
$script:LastDesktopKey = $null
$script:LastTopmostRefresh = [DateTime]::MinValue
$script:ReadFailureNotified = $false
$script:ShuttingDown = $false

function Show-FatalMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        [void][System.Windows.MessageBox]::Show(
            $Message,
            'Virtual Desktop Indicator',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
    catch {
        Write-Error $Message
    }
}

function Release-InstanceMutex {
    if ($null -eq $script:InstanceMutex) {
        return
    }

    try {
        $script:InstanceMutex.ReleaseMutex()
    }
    catch {
        # The mutex might already have been released during abnormal shutdown.
    }
    finally {
        $script:InstanceMutex.Dispose()
        $script:InstanceMutex = $null
    }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Error 'VirtualDesktopIndicator.ps1 can only run on Windows.'
    exit 1
}

try {
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-Error "Could not load the Windows desktop UI assemblies: $($_.Exception.Message)"
    exit 1
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    Show-FatalMessage @'
This script must run in STA mode.

Start it with:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "C:\path\VirtualDesktopIndicator.ps1"
'@
    exit 1
}

$createdNew = $false
try {
    $script:InstanceMutex = [System.Threading.Mutex]::new(
        $true,
        'Local\VirtualDesktopIndicator.PowerShell',
        [ref]$createdNew
    )
}
catch {
    Show-FatalMessage "Could not create the single-instance lock: $($_.Exception.Message)"
    exit 1
}

if (-not $createdNew) {
    Show-FatalMessage 'Virtual Desktop Indicator is already running. Check the system tray.'
    $script:InstanceMutex.Dispose()
    $script:InstanceMutex = $null
    exit 0
}

$moduleInstallHelp = @'
The required VirtualDesktop module (the PowerShell Gallery package for PSVirtualDesktop) is not available.

Open PowerShell and run:
Install-Module -Name VirtualDesktop -Scope CurrentUser

Then start this script again. If an older copy is installed but no longer works after a Windows update, run:
Update-Module -Name VirtualDesktop

Project page:
https://github.com/MScholtes/PSVirtualDesktop
'@

try {
    if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
        throw $moduleInstallHelp
    }

    Import-Module VirtualDesktop -ErrorAction Stop

    $requiredCommands = @(
        'Get-CurrentDesktop',
        'Get-DesktopIndex',
        'Get-DesktopName',
        'Pin-Window'
    )
    $missingCommands = @(
        $requiredCommands | Where-Object {
            $null -eq (Get-Command -Name $_ -ErrorAction SilentlyContinue)
        }
    )

    if ($missingCommands.Count -gt 0) {
        throw "The installed VirtualDesktop module is missing: $($missingCommands -join ', ').`n`n$moduleInstallHelp"
    }
}
catch {
    Show-FatalMessage $_.Exception.Message
    Release-InstanceMutex
    exit 2
}

try {
    if (-not ('VirtualDesktopIndicator.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace VirtualDesktopIndicator
{
    public static class NativeMethods
    {
        [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
        private static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
        private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr value);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr value);

        public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex)
        {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hWnd, nIndex)
                : GetWindowLong32(hWnd, nIndex);
        }

        public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr value)
        {
            return IntPtr.Size == 8
                ? SetWindowLongPtr64(hWnd, nIndex, value)
                : SetWindowLong32(hWnd, nIndex, value);
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetWindowPos(
            IntPtr hWnd,
            IntPtr hWndInsertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }
}
'@
    }
}
catch {
    Show-FatalMessage "Could not initialize the Windows API helper: $($_.Exception.Message)"
    Release-InstanceMutex
    exit 2
}

function Get-CurrentDesktopState {
    $desktop = Get-CurrentDesktop -ErrorAction Stop
    if ($null -eq $desktop) {
        throw 'Get-CurrentDesktop returned no desktop.'
    }

    $index = [int](Get-DesktopIndex -Desktop $desktop -ErrorAction Stop)
    if ($index -lt 0) {
        throw 'The current virtual desktop index could not be resolved.'
    }

    $name = [string](Get-DesktopName -Desktop $desktop -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "Desktop $($index + 1)"
    }

    [pscustomobject]@{
        Index = $index
        Name  = $name
        Key   = "$index`n$name"
    }
}

function New-DesktopTrayIcon {
    param(
        [Parameter(Mandatory = $true)]
        [int]$DesktopIndex
    )

    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $backgroundBrush = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::FromArgb(255, 37, 99, 235)
    )
    $textBrush = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::White
    )
    $font = $null
    $format = $null

    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillEllipse($backgroundBrush, 2, 2, 60, 60)

        $numberText = [string]($DesktopIndex + 1)
        if ($numberText.Length -gt 2) {
            $numberText = '+'
        }

        $fontSize = if ($numberText.Length -eq 1) { 36 } else { 29 }
        $font = [System.Drawing.Font]::new(
            'Segoe UI',
            $fontSize,
            [System.Drawing.FontStyle]::Bold,
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rectangle = New-Object System.Drawing.RectangleF -ArgumentList 0, 0, 64, 61
        $graphics.DrawString($numberText, $font, $textBrush, $rectangle, $format)

        $nativeHandle = $bitmap.GetHicon()
        try {
            return [System.Drawing.Icon]::FromHandle($nativeHandle).Clone()
        }
        finally {
            [void][VirtualDesktopIndicator.NativeMethods]::DestroyIcon($nativeHandle)
        }
    }
    finally {
        if ($null -ne $format) { $format.Dispose() }
        if ($null -ne $font) { $font.Dispose() }
        $textBrush.Dispose()
        $backgroundBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-OverlayPosition {
    if ($null -eq $script:OverlayWindow -or -not $script:OverlayWindow.IsVisible) {
        return
    }

    $script:OverlayWindow.UpdateLayout()
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $script:OverlayWindow.Left = [Math]::Max(
        $workArea.Left,
        $workArea.Right - $script:OverlayWindow.ActualWidth - $OverlayMargin
    )
    $script:OverlayWindow.Top = $workArea.Top + $OverlayMargin
}

function Set-OverlayTopmost {
    if ($script:OverlayHwnd -eq [IntPtr]::Zero -or -not $script:OverlayWindow.IsVisible) {
        return
    }

    $hWndTopmost = [IntPtr](-1)
    $noSize = 0x0001
    $noMove = 0x0002
    $noActivate = 0x0010
    [void][VirtualDesktopIndicator.NativeMethods]::SetWindowPos(
        $script:OverlayHwnd,
        $hWndTopmost,
        0,
        0,
        0,
        0,
        [uint32]($noSize -bor $noMove -bor $noActivate)
    )
    $script:LastTopmostRefresh = [DateTime]::UtcNow
}

function Set-OverlayExtendedStyles {
    if ($script:OverlayHwnd -eq [IntPtr]::Zero) {
        return
    }

    $gwlExStyle = -20
    $wsExTransparent = 0x00000020
    $wsExToolWindow = 0x00000080
    $wsExNoActivate = 0x08000000
    $style = [VirtualDesktopIndicator.NativeMethods]::GetWindowLongPtr(
        $script:OverlayHwnd,
        $gwlExStyle
    ).ToInt64()
    $style = $style -bor $wsExTransparent -bor $wsExToolWindow -bor $wsExNoActivate
    [void][VirtualDesktopIndicator.NativeMethods]::SetWindowLongPtr(
        $script:OverlayHwnd,
        $gwlExStyle,
        [IntPtr]$style
    )

    $noSize = 0x0001
    $noMove = 0x0002
    $noActivate = 0x0010
    $frameChanged = 0x0020
    [void][VirtualDesktopIndicator.NativeMethods]::SetWindowPos(
        $script:OverlayHwnd,
        [IntPtr](-1),
        0,
        0,
        0,
        0,
        [uint32]($noSize -bor $noMove -bor $noActivate -bor $frameChanged)
    )
}

function Set-TrayToolTip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DesktopName
    )

    $text = "Virtual desktop: $DesktopName"
    if ($text.Length -gt 63) {
        $text = $text.Substring(0, 62) + [char]0x2026
    }
    $script:TrayIcon.Text = $text
}

function Update-DesktopIndicator {
    try {
        $state = Get-CurrentDesktopState
        $script:ReadFailureNotified = $false

        if ($state.Key -ne $script:LastDesktopKey) {
            $script:LastDesktopKey = $state.Key
            $script:OverlayText.Text = $state.Name
            $script:OverlayWindow.Title = "Virtual Desktop - $($state.Name)"
            Set-TrayToolTip -DesktopName $state.Name

            $newIcon = New-DesktopTrayIcon -DesktopIndex $state.Index
            $oldIcon = $script:TrayIcon.Icon
            $script:TrayIcon.Icon = $newIcon
            if ($null -ne $oldIcon) {
                $oldIcon.Dispose()
            }

            Set-OverlayPosition
            Set-OverlayTopmost
        }

        if (
            $script:OverlayWindow.IsVisible -and
            ([DateTime]::UtcNow - $script:LastTopmostRefresh).TotalSeconds -ge 2
        ) {
            Set-OverlayTopmost
        }
    }
    catch {
        if (-not $script:ReadFailureNotified) {
            $script:ReadFailureNotified = $true
            $message = "Could not read the current virtual desktop. Try updating the VirtualDesktop module.`n`n$($_.Exception.Message)"
            Write-Warning $message
            if ($null -ne $script:TrayIcon -and $script:TrayIcon.Visible) {
                $script:TrayIcon.ShowBalloonTip(
                    5000,
                    'Virtual Desktop Indicator',
                    $message,
                    [System.Windows.Forms.ToolTipIcon]::Warning
                )
            }
        }
    }
}

function Show-Overlay {
    if (-not $script:OverlayWindow.IsVisible) {
        $script:OverlayWindow.Show()
    }
    Set-OverlayExtendedStyles
    Set-OverlayPosition
    Set-OverlayTopmost
    $script:ToggleOverlayMenuItem.Text = 'Hide Overlay'
}

function Hide-Overlay {
    if ($script:OverlayWindow.IsVisible) {
        $script:OverlayWindow.Hide()
    }
    $script:ToggleOverlayMenuItem.Text = 'Show Overlay'
}

function Toggle-Overlay {
    if ($script:OverlayWindow.IsVisible) {
        Hide-Overlay
    }
    else {
        Show-Overlay
    }
}

function Request-IndicatorExit {
    if ($script:ShuttingDown) {
        return
    }

    $script:ShuttingDown = $true
    if ($null -ne $script:PollTimer) {
        $script:PollTimer.Stop()
    }
    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.Visible = $false
    }
    if ($null -ne $script:Dispatcher) {
        $script:Dispatcher.BeginInvokeShutdown(
            [System.Windows.Threading.DispatcherPriority]::Normal
        )
    }
}

function Clear-IndicatorResources {
    if ($null -ne $script:PollTimer) {
        $script:PollTimer.Stop()
        $script:PollTimer = $null
    }

    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        if ($null -ne $script:TrayIcon.Icon) {
            $script:TrayIcon.Icon.Dispose()
            $script:TrayIcon.Icon = $null
        }
        $script:TrayIcon.Dispose()
        $script:TrayIcon = $null
    }

    if ($null -ne $script:TrayMenu) {
        $script:TrayMenu.Dispose()
        $script:TrayMenu = $null
    }

    if ($null -ne $script:OverlayWindow) {
        try { $script:OverlayWindow.Close() } catch { }
        $script:OverlayWindow = $null
    }

    Release-InstanceMutex
}

try {
    $initialState = Get-CurrentDesktopState
}
catch {
    Show-FatalMessage "Could not read the current virtual desktop.`n`n$($_.Exception.Message)`n`nTry: Update-Module -Name VirtualDesktop"
    Release-InstanceMutex
    exit 3
}

try {
    $script:Dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

    $script:OverlayWindow = New-Object System.Windows.Window
    $script:OverlayWindow.WindowStyle = [System.Windows.WindowStyle]::None
    $script:OverlayWindow.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $script:OverlayWindow.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $script:OverlayWindow.AllowsTransparency = $true
    $script:OverlayWindow.Background = [System.Windows.Media.Brushes]::Transparent
    $script:OverlayWindow.ShowInTaskbar = $false
    $script:OverlayWindow.ShowActivated = $false
    $script:OverlayWindow.Topmost = $true
    $script:OverlayWindow.Focusable = $false
    $script:OverlayWindow.IsHitTestVisible = $false

    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(190, 24, 24, 27)
    )
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(95, 255, 255, 255)
    )
    $border.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 1
    $border.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 7
    $border.Padding = New-Object System.Windows.Thickness -ArgumentList 13, 7, 13, 8

    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $shadow.BlurRadius = 10
    $shadow.ShadowDepth = 2
    $shadow.Opacity = 0.38
    $border.Effect = $shadow

    $script:OverlayText = New-Object System.Windows.Controls.TextBlock
    $script:OverlayText.Text = $initialState.Name
    $script:OverlayText.Foreground = [System.Windows.Media.Brushes]::White
    $script:OverlayText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $script:OverlayText.FontSize = 16
    $script:OverlayText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $script:OverlayText.MaxWidth = 420
    $script:OverlayText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $script:OverlayText.TextWrapping = [System.Windows.TextWrapping]::NoWrap
    $border.Child = $script:OverlayText
    $script:OverlayWindow.Content = $border

    $script:OverlayWindow.add_SourceInitialized({
        $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $script:OverlayWindow
        $script:OverlayHwnd = $helper.Handle
        Set-OverlayExtendedStyles
    })
    $script:OverlayWindow.add_SizeChanged({ Set-OverlayPosition })

    $script:TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:ToggleOverlayMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:ToggleOverlayMenuItem.Text = if ($StartHidden) { 'Show Overlay' } else { 'Hide Overlay' }
    $script:ToggleOverlayMenuItem.add_Click({ Toggle-Overlay })
    [void]$script:TrayMenu.Items.Add($script:ToggleOverlayMenuItem)
    [void]$script:TrayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitMenuItem.Text = 'Exit'
    $exitMenuItem.add_Click({ Request-IndicatorExit })
    [void]$script:TrayMenu.Items.Add($exitMenuItem)

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.ContextMenuStrip = $script:TrayMenu
    $script:TrayIcon.Icon = New-DesktopTrayIcon -DesktopIndex $initialState.Index
    Set-TrayToolTip -DesktopName $initialState.Name
    $script:TrayIcon.add_DoubleClick({ Toggle-Overlay })
    $script:TrayIcon.Visible = $true

    $script:OverlayWindow.Show()
    $script:OverlayWindow.UpdateLayout()
    Set-OverlayPosition
    Set-OverlayTopmost

    try {
        Pin-Window -Hwnd $script:OverlayHwnd -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Could not pin the overlay to every virtual desktop. Try updating the VirtualDesktop module.`n`n$($_.Exception.Message)"
    }

    if ($StartHidden) {
        Hide-Overlay
    }

    $script:LastDesktopKey = $initialState.Key
    $script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PollTimer.Interval = [TimeSpan]::FromMilliseconds($PollIntervalMilliseconds)
    $script:PollTimer.add_Tick({ Update-DesktopIndicator })
    $script:PollTimer.Start()

    [System.Windows.Threading.Dispatcher]::Run()
}
catch {
    Show-FatalMessage $_.Exception.Message
}
finally {
    Clear-IndicatorResources
}
