# Apple Shortcut Setup for Voice-Driven Development

This guide covers how to set up the Apple Shortcut that triggers the voice-driven development pipeline. The shortcut records your voice on iPhone, transcribes it, and sends the text to your Mac via SSH where `dev-pilot` generates (and optionally executes) an implementation plan.

## Prerequisites

- iPhone with the Shortcuts app
- Mac with Remote Login enabled
- The `dev-pilot` CLI built on the Mac (`make build` from the project root)
- SSH key authentication configured between iPhone and Mac

## 1. Enable Remote Login on the Mac

1. Open **System Settings**
2. Go to **General → Sharing**
3. Enable **Remote Login**
4. Under "Allow access for", choose either "All users" or add your specific user account
5. Note the hostname shown (e.g., `bills-macbook.local`) — you'll need this for the shortcut

To verify it's working, open Terminal and run:

```bash
ssh bill@localhost
```

If you can connect, Remote Login is configured correctly.

## 2. Set Up SSH Key Authentication

The Apple Shortcut needs passwordless SSH access to your Mac. Generate a key pair on the iPhone and add the public key to the Mac.

### Option A: Generate Key on iPhone via Shortcuts

1. Create a temporary shortcut with the **Run Script over SSH** action
2. Connect to your Mac using password authentication the first time
3. The Shortcuts app will offer to generate and install an SSH key pair

### Option B: Manual Key Setup

On the Mac, ensure `~/.ssh/authorized_keys` exists:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

When you first use the "Run Script over SSH" action in Shortcuts, iOS will prompt you for the password and can store credentials/keys for future use.

## 3. Create the Apple Shortcut

Open the **Shortcuts** app on your iPhone and create a new shortcut:

### Step 1: Record Audio

Add the **Record Audio** action.

- This opens the microphone and records until you tap stop
- Describe your development task naturally (e.g., "Fix the bug where waypoints disappear after saving the flight plan")

### Step 2: Transcribe Audio

Add the **Transcribe Audio** action.

- Input: the audio from the previous step
- This converts your speech to text using on-device transcription

### Step 3: Run Script over SSH

Add the **Run Script over SSH** action with these settings:

| Setting         | Value                                                                                         |
|-----------------|-----------------------------------------------------------------------------------------------|
| **Host**        | Your Mac's hostname or IP (e.g., `bills-macbook.local`)                                       |
| **Port**        | 22                                                                                            |
| **User**        | `bill`                                                                                        |
| **Authentication** | SSH Key                                                                                    |
| **Script**      | `/Users/bill/Developer/personal/claude-tools/voice-plan.sh '<Transcribed Text>'`              |

Replace `<Transcribed Text>` with the variable from the Transcribe Audio step by tapping the text field and inserting the transcription variable.

### Step 4 (Optional): Show Result

Add a **Show Result** action to display the SSH output (plan generation confirmation) on your phone.

### Naming the Shortcut

Name it something Siri-friendly like **"Dev Plan"** so you can trigger it by saying "Hey Siri, Dev Plan".

## 4. Auto-Execute Variant

To create a shortcut that generates AND immediately executes the plan, change the SSH script to:

```
/Users/bill/Developer/personal/claude-tools/voice-plan.sh --execute '<Transcribed Text>'
```

Consider creating two shortcuts:
- **"Dev Plan"** — generates the plan only (for review before execution)
- **"Dev Execute"** — generates and immediately executes the plan

## 5. Testing

### Test SSH Connectivity

From your iPhone, create a simple shortcut with just a "Run Script over SSH" action that runs `echo "hello"`. Verify it connects and returns output.

### Test the Pipeline Locally

On the Mac, test the full pipeline with sample voice text:

```bash
# Test plan generation
/Users/bill/Developer/personal/claude-tools/voice-plan.sh "Add a logout button to the settings page"

# Test plan + execute
/Users/bill/Developer/personal/claude-tools/voice-plan.sh --execute "Add a logout button to the settings page"
```

### Test from iPhone

1. Run the shortcut
2. Speak a development task
3. Verify a plan document appears in the target repo's `docs/proposed/` directory on the Mac

## 6. Troubleshooting

### SSH Connection Fails

- **"Connection refused"**: Verify Remote Login is enabled on the Mac (System Settings → General → Sharing)
- **"Host not found"**: Try using the Mac's IP address instead of hostname. Find it with `ifconfig | grep "inet "` on the Mac
- **"Permission denied"**: SSH key authentication isn't configured. Re-check the key setup in Section 2
- **Timeout**: Ensure both devices are on the same network, or configure port forwarding if connecting remotely

### Transcription Issues

- Voice transcription will have errors — the system is designed to handle this. `dev-pilot` uses recent commit history and repo context to infer intent
- Speak clearly and use project-specific terminology
- For complex requests, pause briefly between phrases
- If the transcription is consistently poor, check that the Shortcuts app has microphone permissions (Settings → Shortcuts → Microphone)

### `dev-pilot` Not Found or Fails

- Ensure the CLI is built: run `make build` from `/Users/bill/Developer/personal/claude-tools/`
- Verify the binary exists: `ls cli/.build/release/dev-pilot`
- SSH sessions may not load your shell profile. If `claude` is not found, ensure it's in a standard PATH location or update `voice-plan.sh` to source your profile

### Plan Not Generated

- Check that `repos.json` exists in the project root with valid repository entries
- Verify the Claude CLI is installed and working: `claude --version`
- Check for errors in the SSH output (add a "Show Result" action to the shortcut)

### Shortcut Runs but Nothing Happens on Mac

- Add a "Show Result" action after the SSH step to see any error output
- Test the SSH command manually from Terminal first
- Check that `voice-plan.sh` is executable: `chmod +x voice-plan.sh`
