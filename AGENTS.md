# Repository Guidelines

## Project Structure & Module Organization

This repository currently has no application source, tests, or build configuration. Add new code under `src/`, automated tests under `tests/`, and static files under `assets/` when those directories become necessary. Keep related features together (for example, `src/employees/` and `tests/employees/`) and document any new top-level directory in this guide or a README. The existing `.agents/`, `.codex/`, and `.aws/` directories are reserved for local tooling and configuration; do not place application code there.

## Build, Test, and Development Commands

No build, test, lint, or run commands are configured yet. When introducing a framework, add its manifest and a short README with exact setup and execution commands. Prefer one discoverable command for each routine task, such as `npm run dev`, `npm test`, and `npm run build` for a Node.js project. Do not assume those example commands work until they are defined in the manifest.

## Coding Style & Naming Conventions

Follow the formatter and linter selected with the first implementation, and commit their configuration so local and CI results match. Until then, use consistent indentation within each file, descriptive names, and feature-oriented file placement. Name test files after the module they cover, using the convention of the chosen test framework. Avoid adding a second formatting style without updating existing code and this guide.

## Testing Guidelines

There is no test framework or coverage threshold in this repository yet. Add focused tests with each behavior change once a framework is configured. Cover expected behavior and important failure cases, and record the test command in the README. Run the relevant tests before opening a pull request; explain any tests that cannot be run.

## Commit & Pull Request Guidelines

No commit history is available to establish an existing message pattern. Use short, imperative commit subjects, such as `Add employee search`, and keep unrelated changes in separate commits. Pull requests should explain the change, link a relevant issue when one exists, list verification performed, and include screenshots for visible UI changes. Call out configuration or migration steps that reviewers need to reproduce the result.
