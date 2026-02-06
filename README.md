# EventProcessor

macOS app that processes and stores events, and can generate LLM output from them.

## Build & run

### Prereqs
- Xcode (macOS 14+ recommended)
- Tuist (`brew install tuist`)

### Generate the Xcode project
```bash
tuist install
tuist generate
open EventProcessor.xcodeproj
```

### Run
In Xcode, select the `EventProcessor` scheme, choose a **My Mac** destination, then **Run** (⌘R).

## Troubleshooting
- If packages don’t resolve, run `tuist install` again and re-generate.
- If Xcode shows indexing/build issues, try **Product → Clean Build Folder** and rebuild.