# Epic: openQA Retrigger & Flakiness Mitigation Plan

## 1. Problem Statement
The "retrigger and pray" anti-pattern is prevalent among reviewers (especially junior test reviewers). Faced with complex failures and overwhelmed by the potential variables (test code changes, needle changes, product changes, OS changes, infrastructure, or sporadic issues), reviewers often opt for the path of least resistance: clicking "Retry" without deep investigation. 

This behavior stems from high investigation friction, cognitive overload, and a general lack of trust in automated triage tools (e.g., `auto-review` scripts). While retriggering feels like a quick workaround, it actively harms the ecosystem by masking underlying product regressions, burning valuable compute capacity, and subverting openQA's mission as an authoritative quality gateway.

## 2. Root Causes & Motivations
* **Unbalanced Friction:** Deep log analysis takes 30 minutes; clicking "Retry" takes 1 second. Without visible feedback on execution cost or limits, retrying feels "free."
* **Trust Deficit in Automation:** Reviewers resist standalone scripts or bots because black-box automation feels risky or disconnected from their workflow. They prefer manual intervention even when it's inefficient.
* **Subverting Escalation:** Workarounds (like manual restarts) are favored over correcting Bugzilla severity/blocker flags, leaving critical issues improperly prioritized.
* **"Automation by Default" Gap:** Current tooling expects reviewers to opt-in or run external scripts manually, rather than embedding automated triage seamlessly into the openQA web UI workflow.
* **Signal Corruption via "Retry N Times":** Simply allowing users to "Retry N times until green" corrupts pipeline trust. If a test fails 4 times and passes on the 5th, declaring it "green" creates a false sense of security while actively masking real product regressions, timing issues, or race conditions.

## 3. Strategic & Tooling Improvements

To address these issues and align with our strategic pillars (*Automation by Default*, *System-Wide Perspective*), the following initiatives are proposed:

### 3.1. Process & Policy Updates
* **Actionable Retry Guidelines:** Establish and document clear rules stating that manual retries are only valid when accompanied by a test/needle change or a confirmed infrastructure incident.
* **Junior Mentorship & Triage Paths:** Create clear escalation paths so junior reviewers don't feel pressured to resolve flaky or complex runs single-handedly, encouraging them to investigate rather than blind-retry.

### 3.2. openQA Web UI Enhancements
* **Mandatory Retry Context:** Require users to select a reason (e.g., *Needle Updated*, *Code Changed*, *Known Infra Outage*) via a dropdown/modal before permitting a retry. This rationale must be logged and displayed on the job page.
* **Cost & Attempt Visibility:** Display resource usage (e.g., estimated worker hours, queue impact) and a prominent "Retry Attempt Count" on the job interface to introduce healthy psychological friction.
* **Intelligent Retry Rate-Limiting:** Block consecutive manual retries on the exact same state unless openQA detects a fresh commit, a needle change, or a forced admin override.

### 3.3. Surrounding Tooling Integration (`os-autoinst-scripts` / `qem-bot`)
* **In-UI Auto-Review Predictions:** Surface `auto-review` regex matches directly in the openQA UI as suggested labels or bug links. This turns "scary external automation" into highly visible, actionable hints right where the user is looking.
* **Flakiness Scoring:** Calculate and display historical module stability on the job page. Reviewers can instantly spot known flaky tests versus novel regressions, aiding their decision process.

### 3.4. Transforming the "Retry N Times" Concept
Instead of a naive loop, we will transform the "retry N times" request into diagnostic and backend capabilities:
* **Flakiness Profiler (Diagnostic Mode):** Allow reviewers to schedule a batch of $N$ parallel/sequential runs specifically to measure **stability percentage**. The output provides an empirical confidence score (e.g., "Failed 3/10 times") but does *not* alter the original failed job's gatekeeper status.
* **Infra-Only Auto-Retry:** Implement backend logic where openQA automatically retries a job up to $N$ times *only* when the failure is definitively matched to an infrastructure fault (e.g., hypervisor timeout, worker disconnect, QEMU crash)—never on test assertions.
* **Annotated Pipeline Retries:** If external tooling retries a job to force a pass, openQA must render a prominent **"Passed with Retries ($k$/$N$)"** badge rather than a clean green checkmark, alerting release teams to underlying instability.
