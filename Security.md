## Security & Privacy – Quick Notes

### Key risks (high level)
- **1. Local data storage**  
  - Logs and LLM outputs are written to a local SQLite database.  
  - Risk: sensitive values or identifiers could be stored unencrypted and accessible to other local users or malware.

- **2. Network transmission to backend**  
  - `LogSyncManager` and the uploader send aggregated events to a remote service (e.g. Firestore).  
  - Risk: if transport security or auth rules are misconfigured, logs could be intercepted or read by unauthorized parties.

- **3. LLM prompt/response content**  
  - Values are sent to the LLM backend to generate text.  
  - Risk: prompts or generated text may contain sensitive information; logging or storing them long-term increases privacy exposure.

---

### About `GoogleService-Info.plist`

- `GoogleService-Info.plist` is **not considered a secret** in this app.  
- It contains **public client configuration** (project ID, bundle ID, API key that should be restricted on the backend), not server credentials or passwords.  
- In a correctly configured Firebase project:
  - The API key is **restricted to this bundle ID and platform**.
  - All sensitive access is controlled by **Firebase security rules and authentication**, not by keeping this plist private.  
- It should still be reviewed and kept consistent with Firebase console settings, but committing it to the repository is **not itself a security threat**.

