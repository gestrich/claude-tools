#!/bin/bash

# Phased implementation automation script (with streaming output)
# Usage: ./phased-implementation-streaming.sh <planning-document.md> [max-minutes]

set -e

# JSON schema for structured output - tells us how many steps remain
JSON_SCHEMA='{"type":"object","properties":{"remainingSteps":{"type":"integer","description":"Number of incomplete phases remaining in the plan"}},"required":["remainingSteps"]}'

# Define clauded command - returns JSON with structured output
clauded() {
    caffeinate -dimsu claude --dangerously-skip-permissions -p --verbose \
        --output-format json \
        --json-schema "$JSON_SCHEMA" \
        "$@"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Timer functions
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

# Global timer variables
SCRIPT_START_TIME=$(date +%s)
PHASE_START_TIME=0
TIMER_PID=0

# Start a live timer display in the background
start_timer() {
    PHASE_START_TIME=$(date +%s)
    (
        while true; do
            local now=$(date +%s)
            local phase_elapsed=$((now - PHASE_START_TIME))
            local total_elapsed=$((now - SCRIPT_START_TIME))
            printf "\r${CYAN}⏱  Phase: %s | Total: %s${NC}   " \
                "$(format_time $phase_elapsed)" \
                "$(format_time $total_elapsed)"
            sleep 1
        done
    ) &
    TIMER_PID=$!
}

# Stop the live timer
stop_timer() {
    if [ $TIMER_PID -ne 0 ]; then
        kill $TIMER_PID 2>/dev/null || true
        wait $TIMER_PID 2>/dev/null || true
        TIMER_PID=0
        printf "\r%-50s\r" " "  # Clear the timer line
    fi
}

# Cleanup on exit
cleanup() {
    stop_timer
}
trap cleanup EXIT

# Default max runtime (45 minutes in seconds)
MAX_RUNTIME_SECONDS=$((45 * 60))

# Parse arguments
if [ $# -lt 1 ]; then
    # No argument provided - find latest modified file in docs/proposed
    PROPOSED_DIR="docs/proposed"

    if [ ! -d "$PROPOSED_DIR" ]; then
        echo -e "${RED}Error: Directory not found: $PROPOSED_DIR${NC}"
        echo "Usage: $0 <planning-document.md> [max-minutes]"
        exit 1
    fi

    # Find the most recently modified file in docs/proposed
    LATEST_FILE=$(ls -t "$PROPOSED_DIR"/*.md 2>/dev/null | head -1)

    if [ -z "$LATEST_FILE" ]; then
        echo -e "${RED}Error: No .md files found in $PROPOSED_DIR${NC}"
        echo "Usage: $0 <planning-document.md> [max-minutes]"
        exit 1
    fi

    echo -e "${BLUE}No planning document specified.${NC}"
    echo -e "Latest modified file in ${GREEN}$PROPOSED_DIR${NC}:"
    echo -e "  ${YELLOW}$LATEST_FILE${NC}"
    echo
    read -p "Use this file? (y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${RED}Aborted.${NC}"
        echo "Usage: $0 <planning-document.md> [max-minutes]"
        exit 1
    fi

    PLANNING_DOC="$LATEST_FILE"
else
    PLANNING_DOC="$1"

    if [ $# -ge 2 ]; then
        MAX_RUNTIME_SECONDS=$(($2 * 60))
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
echo -e "Max runtime: ${GREEN}$(format_time $MAX_RUNTIME_SECONDS)${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Function to run a single phase
# Sets global REMAINING_STEPS variable with the count from Claude's response
run_phase() {
    local phase_num=$1

    echo -e "${YELLOW}Starting Phase $phase_num${NC}"
    echo -e "${BLUE}--------------------------------------------------${NC}"

    # Construct the instruction for clauded
    local instruction="1. Look at $PLANNING_DOC_ABS for background. 2. Identify the next phase to complete. 3. Complete the phase and ONLY that phase. 4. Make sure you can successfully build. 5. Update the markdown with what is completed and any relevant technical notes. 6. Commit your changes. When returning remainingSteps, count how many phases are still incomplete in the plan."

    echo -e "${BLUE}Running clauded with instruction...${NC}"
    echo

    # Start the live timer
    start_timer

    # Run clauded and capture the JSON output
    local response
    local exit_code=0
    response=$(clauded "$instruction" 2>&1) || exit_code=$?

    # Stop the timer and calculate elapsed time
    stop_timer
    local phase_end=$(date +%s)
    local phase_elapsed=$((phase_end - PHASE_START_TIME))
    local total_elapsed=$((phase_end - SCRIPT_START_TIME))

    if [ $exit_code -eq 0 ]; then
        echo

        # Parse remainingSteps from structured_output
        # With --verbose, output is a JSON array - result is the last element
        REMAINING_STEPS=$(echo "$response" | jq -r '.[-1].structured_output.remainingSteps // -1')

        if [ "$REMAINING_STEPS" = "-1" ] || [ -z "$REMAINING_STEPS" ]; then
            echo -e "${YELLOW}Warning: Could not parse remainingSteps from response${NC}"
            REMAINING_STEPS=-1
        fi

        echo -e "${GREEN}Phase $phase_num completed successfully${NC}"
        echo -e "${CYAN}⏱  Phase time: $(format_time $phase_elapsed) | Total: $(format_time $total_elapsed)${NC}"
        echo -e "${BLUE}Remaining steps: ${YELLOW}$REMAINING_STEPS${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        echo
        return 0
    else
        echo
        echo -e "${RED}Phase $phase_num failed${NC}"
        echo -e "${CYAN}⏱  Phase time: $(format_time $phase_elapsed) | Total: $(format_time $total_elapsed)${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        echo
        REMAINING_STEPS=-1
        return 1
    fi
}

# Main loop
phase_count=1
REMAINING_STEPS=-1

while true; do
    # Check if we've exceeded max runtime
    elapsed=$(($(date +%s) - SCRIPT_START_TIME))
    remaining_time=$((MAX_RUNTIME_SECONDS - elapsed))

    if [ $remaining_time -le 0 ]; then
        echo -e "${YELLOW}Time limit reached ($(format_time $MAX_RUNTIME_SECONDS))${NC}"
        break
    fi

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}Iteration $phase_count | Time remaining: $(format_time $remaining_time)${NC}"
    echo -e "${BLUE}==================================================${NC}"

    # Run the phase
    if ! run_phase $phase_count; then
        echo -e "${RED}Stopping due to phase failure${NC}"
        exit 1
    fi

    # Check if all phases are complete
    if [ "$REMAINING_STEPS" = "0" ]; then
        echo -e "${GREEN}All phases complete! (remainingSteps: 0)${NC}"
        break
    fi

    # Continue to next phase automatically (headless mode)
    echo -e "${GREEN}Continuing to next phase ($REMAINING_STEPS remaining)...${NC}"
    sleep 2  # Brief pause between phases

    phase_count=$((phase_count + 1))
done

echo
echo -e "${BLUE}==================================================${NC}"
if [ "$REMAINING_STEPS" = "0" ]; then
    echo -e "${GREEN}✓ All phases completed successfully!${NC}"
else
    echo -e "${YELLOW}Time limit reached - $REMAINING_STEPS steps may remain${NC}"
fi
echo -e "${BLUE}==================================================${NC}"
FINAL_TIME=$(($(date +%s) - SCRIPT_START_TIME))
echo -e "Total iterations: ${GREEN}$phase_count${NC}"
echo -e "Total time: ${CYAN}$(format_time $FINAL_TIME)${NC}"
echo -e "Planning document: ${GREEN}$PLANNING_DOC_ABS${NC}"
echo

# Move completed spec to docs/completed
if [ "$REMAINING_STEPS" = "0" ]; then
    COMPLETED_DIR="docs/completed"
    mkdir -p "$COMPLETED_DIR"
    mv "$PLANNING_DOC_ABS" "$COMPLETED_DIR/"
    echo -e "${GREEN}Moved spec to ${COMPLETED_DIR}/$(basename "$PLANNING_DOC_ABS")${NC}"
fi
