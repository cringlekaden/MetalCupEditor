# Stage 4 policy tests

`ProjectPolicyTests.swift` is a small executable test harness compiled against the production project-document and path-policy sources. It verifies canonical decoding, explicit override decoding, selected-location creation, open-in-place behavior, portable override paths, and production decoding of the tracked validation project and scene.

It intentionally remains outside the Editor application target. The Editor project has no shared unit-test scheme, and Stage 4 does not alter schemes solely to expose tests.

`verify_repository_resources.sh` checks the recorded canonical shader hashes and exact file set, the 18-file asset inventory, validation-project structure, PBX ownership, and Git tracking. Run it from either repository after both Stage 4 changes have been staged or committed.
