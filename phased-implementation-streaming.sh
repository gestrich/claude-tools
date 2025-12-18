#!/bin/bash

# Phased implementation automation script (with streaming output)
# Usage: ./phased-implementation-streaming.sh <planning-document.md> [max-phases]

set -e

# Define clauded command (expand the alias) - with streaming JSON output
clauded() {
    caffeinate -dimsu claude --dangerously-skip-permissions -p --verbose --output-format stream-json "$@"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default max phase count
MAX_PHASES=10

# Parse arguments
if [ $# -lt 1 ]; then
    # No argument provided - find latest modified file in docs/proposed
    PROPOSED_DIR="docs/proposed"

    if [ ! -d "$PROPOSED_DIR" ]; then
        echo -e "${RED}Error: Directory not found: $PROPOSED_DIR${NC}"
        echo "Usage: $0 <planning-document.md> [max-phases]"
        exit 1
    fi

    # Find the most recently modified file in docs/proposed
    LATEST_FILE=$(ls -t "$PROPOSED_DIR"/*.md 2>/dev/null | head -1)

    if [ -z "$LATEST_FILE" ]; then
        echo -e "${RED}Error: No .md files found in $PROPOSED_DIR${NC}"
        echo "Usage: $0 <planning-document.md> [max-phases]"
        exit 1
    fi

    echo -e "${BLUE}No planning document specified.${NC}"
    echo -e "Latest modified file in ${GREEN}$PROPOSED_DIR${NC}:"
    echo -e "  ${YELLOW}$LATEST_FILE${NC}"
    echo
    read -p "Use this file? (y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${RED}Aborted.${NC}"
        echo "Usage: $0 <planning-document.md> [max-phases]"
        exit 1
    fi

    PLANNING_DOC="$LATEST_FILE"
else
    PLANNING_DOC="$1"

    if [ $# -ge 2 ]; then
        MAX_PHASES="$2"
    fi
fi

# Validate planning document exists
if [ ! -f "$PLANNING_DOC" ]; then
    echo -e "${RED}Error: Planning document not found: $PLANNING_DOC${NC}"
    exit 1
fi

# Get absolute path for planning document
PLANNING_DOC_ABS=$(cd "$(dirname "$PLANNING_DOC")" && pwd)/$(basename "$PLANNING_DOC")

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Phased Implementation Automation (Streaming)${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Planning document: ${GREEN}$PLANNING_DOC_ABS${NC}"
echo -e "Max phases: ${GREEN}$MAX_PHASES${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Function to run a single phase
run_phase() {
    local phase_num=$1

    echo -e "${YELLOW}Starting Phase $phase_num of $MAX_PHASES${NC}"
    echo -e "${BLUE}--------------------------------------------------${NC}"

    # Construct the instruction for clauded
    #local instruction="/agent-orientation After orientating yourself, do the following 1. Look at $PLANNING_DOC_ABS for background. 2. Identify the next phase to complete. 3. Complete the phase. 4. Make sure you can successfully build. 5. use the CLI target to test new APIs for each phase. 6. Update the markdown with what is completed and any relevant technical notes. 7. commit"
    local instruction="1. Look at $PLANNING_DOC_ABS for background. 2. Identify the next phase to complete. 3. Complete the phase. 4. Make sure you can successfully build. 6. Update the markdown with what is completed and any relevant technical notes. 7. commit"

    echo -e "${BLUE}Running clauded with instruction...${NC}"
    echo

    # Run clauded with the instruction
    if clauded "$instruction"; then
        echo
        echo -e "${GREEN}Phase $phase_num completed successfully${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        echo
        return 0
    else
        echo
        echo -e "${RED}Phase $phase_num failed${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        echo
        return 1
    fi
}

# Main loop
phase_count=1

while [ $phase_count -le $MAX_PHASES ]; do
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}Phase $phase_count/${MAX_PHASES}${NC}"
    echo -e "${BLUE}==================================================${NC}"

    # Run the phase
    if ! run_phase $phase_count; then
        echo -e "${RED}Stopping due to phase failure${NC}"
        exit 1
    fi

    # Continue to next phase automatically (headless mode)
    if [ $phase_count -lt $MAX_PHASES ]; then
        echo -e "${GREEN}Continuing to next phase automatically...${NC}"
        sleep 2  # Brief pause between phases
    fi

    phase_count=$((phase_count + 1))
done

echo
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}Phased implementation completed!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Total phases completed: ${GREEN}$((phase_count - 1))${NC}"
echo -e "Planning document: ${GREEN}$PLANNING_DOC_ABS${NC}"
echo
