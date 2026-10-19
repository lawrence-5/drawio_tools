# Project Policy for AI-Assisted Design and Infrastructure Build

## 1. Scope and Core Principles

This policy applies to document analysis, solution evaluation, detailed design, CDK implementation, environment provisioning, testing, and delivery.

- Base all work on confirmed requirements, company standards, and verifiable evidence.
- Do not independently fill in undecided design details merely to make documents complete, code runnable, or tasks appear finished.
- Clearly identify unreasonable requirements, conflicting information, or technical infeasibility, and explain the evidence. Do not accommodate incorrect premises.
- Do not expand the project scope, introduce additional services, or change approved solutions without authorization.
- Treat AI-generated content as work awaiting review. AI self-review does not replace human approval required by the project.

## 2. Facts, Evidence, and Uncertainty

Clearly classify every conclusion that affects design or implementation as one of the following:

- **Confirmed requirement**: Approved by the project owner or an authorized decision-maker.
- **Documented statement**: Explicitly stated in a source document, but not necessarily approved or still valid.
- **Verification result**: Established through documentation lookup, code inspection, or actual testing.
- **Inference / assumption**: Inferred from limited information and not yet verified.
- **Recommendation**: A candidate approach proposed by AI and not yet adopted.
- **Pending confirmation**: Insufficient information is available to reach a conclusion.

Requirements:

- Support key conclusions with source sections, official links, or verification records. Include relevant versions, dates, and applicability conditions.
- Do not fabricate references, parameters, limits, test records, approval records, or environment information.
- Accurately disclose files that could not be read, unsuccessful tool calls, and actions that were not performed.
- Repeating an assumption across multiple documents does not make it confirmed.
- When sources conflict with each other or with the actual environment, document the conflicts and their impact. Do not independently select whichever interpretation makes it easier to proceed.

## 3. Verification of AWS Technical Information

- Consult official AWS documentation before making claims about AWS service behavior, limits, APIs, CDK properties, or current best practices.
- If AWS Knowledge MCP is configured, use `search_documentation` first, then read the relevant documentation if the search results are insufficient.
- For regional or feature availability, verify using `get_regional_availability` and supplement with official documentation as needed.
- Verify the CDK, dependency, and runtime versions actually used by the project. Do not directly apply examples intended for other versions.
- Treat official examples and default values as references, not automatically as approved project configuration values.
- If documentation is inaccessible or evidence is insufficient, mark the information as "unverified" and specify the additional verification needed. Do not make definitive claims based solely on model memory.
- Cost estimates must state the configuration, usage assumptions, pricing sources, and estimate date. Do not present estimates as actual billed costs.

## 4. Open Questions and Solution Decisions

Maintain a shared register of items pending confirmation, recording at least:

**ID, question, current evidence, candidate options, scope of impact, person responsible for confirmation, status, and confirmed decision.**

- Prioritize questions affecting architecture, security, cost, availability, data retention, and operations.
- In each round, focus on the three to five most important questions and explain why confirmation is needed.
- Compare options using consistent criteria, including requirements fit, complexity, operational burden, cost, and difficulty of future changes.
- Every recommendation must state its applicability conditions, main drawbacks, and unverified assumptions.
- For technical assumptions with significant impact, propose the smallest practical verification exercise with a clear objective.
- An unresolved item blocks only the work that depends on it. Independent work may continue.
- Clearly mark undecided parameters and check them before deployment to prevent example or temporary values from entering the target operational environment.
- User silence, elapsed time, or AI's judgment that something is "reasonable" does not constitute approval.

## 5. Detailed Design Requirements

- Identify confirmed decisions, constraints, and gaps in the basic design before developing the detailed design.
- Follow the company's required templates and level of detail. Generating a `design.md` file does not, by itself, constitute completion of the formal detailed design.
- Where applicable, describe resource purposes, configuration parameters, communication paths, permissions, data processing, error handling, monitoring, backup and recovery, and operational procedures.
- Give each key parameter an explicit value or mark it as pending confirmation. Explain its basis and any differences between environments.
- Establish traceability between requirements, design decisions, implementation tasks, and acceptance criteria.
- Explain why a design item is not applicable. Do not invent content merely to fill a template.
- If the architecture or key parameters remain unconfirmed, produce only a clearly labeled draft. Do not use it as the approved basis for environment provisioning.

## 6. CDK Implementation and Change Management

- Implement the confirmed design. Key configurations in code must be traceable to their design basis.
- If a design cannot be implemented or is incomplete, record the discrepancy and propose changes first. Do not silently alter the design through code.
- Specify dependency versions and environment-specific configurations. Avoid reliance on undocumented local machine state.
- Do not include passwords, tokens, access keys, or other sensitive information in code, design documents, logs, or conversation output.
- Inspect existing files and differences before making changes. Preserve human edits, and do not delete or overwrite existing work without authorization.
- Assess whether refactoring or changes to resource identifiers or configurations could cause resource replacement, deletion, or data impact.
- Keep affected designs, code, tests, and operational procedures consistent so that different artifacts do not describe different systems.
- Make changes in batches that can be reviewed and verified independently. Do not mix in unrelated modifications.

## 7. Operational Authorization and Execution Boundaries

- Distinguish document preparation, code changes, local verification, external queries, and cloud environment changes.
- Permission to sign in to Kiro through an enterprise account does not imply authorization to operate arbitrary cloud resources.
- External API calls must remain within the previously confirmed scope of services, purposes, data, and operations. Reconfirmation is unnecessary while that scope remains unchanged.
- Before deployment, deletion, resource replacement, permission changes, data modification, or other irreversible actions, confirm the specific targets and impacts.
- Before requesting approval, complete the preparation already authorized and provide reviewable changes, verification results, and unresolved issues.
- Before execution, verify the account, Region, environment, target resources, and actual execution identity. Do not rely solely on default configurations.
- State whether an operation will incur costs, upload data, access external services, or change remote state. Do not assume an operation has no side effects based on its command name alone.
- Seek renewed confirmation if the scope or impact of an approved operation changes.
- If an unexpected result occurs, stop the affected operations, preserve evidence, and report it. Do not independently expand permissions or delete resources to "restore normal operation."

## 8. Verification and Infrastructure Build Requirements

- Derive verification activities from requirements and design. Do not write tests solely around the behavior of the generated code.
- Separately check code quality, synthesized templates, key resource properties, proposed changes, and actual behavior after deployment.
- Verification must cover applicable normal flows, failure cases, permission boundaries, and recovery requirements.
- Distinguish successful compilation, successful `cdk synth`, passing tests, successful deployment, and successful business acceptance.
- Do not rely only on snapshot tests. Key requirements need explicit checks or assertions.
- Do not conceal problems by deleting tests, weakening checks, or relaxing permission requirements. If adjustments are necessary, explain their basis and follow the approval process.
- Before provisioning, prepare execution steps, prerequisites, success criteria, stop conditions, and applicable rollback or recovery procedures.
- State the conditions and limitations of rollback plans. Do not assume every change can be reversed without loss.
- For each verification activity, record its objective, method, environment, expected result, actual result, and evidence.
- List checks that were not or could not be performed, explain why, and identify the remaining risks. Do not report them as passed.

## 9. Phase Progression and Completion Reporting

Advance the relevant work only when the following conditions are met:

- **Before formal implementation**: The corresponding design is confirmed, and key issues affecting that implementation have been resolved.
- **Before environment changes**: The proposed changes, execution scope, required verification, and recovery arrangements have been reviewed, and operational authorization has been obtained.
- **Before declaring the infrastructure build complete**: Actual results have been checked, and the agreed provisioning verification has been completed.
- **Before declaring acceptance complete**: The agreed acceptance criteria have been met, and the human confirmation required by the project has been obtained.

Each phase report must state at least:

1. What was completed.
2. What was actually checked or executed, and what evidence is available.
3. What remains inferred, pending confirmation, or unverified.
4. What discrepancies from the design were found.
5. What can proceed next, and what needs confirmation from whom.

Use precise status descriptions such as "draft complete," "code generated," "local verification passed," "deployed," and "acceptance passed." Avoid blanket claims that "everything is complete."
