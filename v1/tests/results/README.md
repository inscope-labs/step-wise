# Acceptance evidence

This directory holds the recorded results of running the behavioral acceptance scenarios against a real model. `v1/utils/sw-release.sh` reads it to decide whether a release is allowed (plan 7.2).

## Recording evidence

```bash
export ANTHROPIC_API_KEY=...
python3 v1/tests/sw_acceptance.py --samples 3 --model <model-id> \
    --results v1/tests/results/<model-id>.json --transcripts transcripts/
```

Commit the results file. Do not use `--filter`: a partial run is recorded as partial and does not count.

## What counts

A file counts only if all of these hold:

- it was recorded against the **current** prompt, features, specs and scenarios (their hashes are stored in the file; a version bump or a `Status` word does not change them, any other edit does)
- it covers **every** scenario, and every one passed
- it used at least 3 samples per scenario and a threshold of at least 0.67
- it is a complete run

A file recorded against older text is reported as *stale* and ignored. You must re-run it.

A current file that **fails** blocks the release until it is re-run or removed. That friction is deliberate: a failure should not disappear quietly. Removing it shows up in version control.

## What this does not prove

The check catches accidents and stale results. It cannot stop someone from editing a results file by hand, and a passing run is regex-and-load-log evidence about one model on one day, not proof that the prompt is followed in general. Read the transcripts.

Check the current state at any time:

```bash
python3 v1/tests/sw_acceptance.py --verify-evidence v1/tests/results --min-models 1
bash v1/utils/sw-release.sh --check --skip-suites
```
