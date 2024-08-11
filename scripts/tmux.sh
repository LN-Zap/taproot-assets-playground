#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Name of the tmux session
SESSION_NAME="taproot-assets-demo"

# Path to the demo script
DEMO_SCRIPT="${DIR}/demo.sh"

# Create a new tmux session
tmux new-session -d -s $SESSION_NAME

# Split the window into three panes with the desired layout
tmux split-window -v -t $SESSION_NAME:0
tmux split-window -h -t $SESSION_NAME:0.1

# Set titles for each pane
tmux select-pane -t $SESSION_NAME:0.0 -T "Demo Script"
tmux select-pane -t $SESSION_NAME:0.1 -T "Docker Logs litd1"
tmux select-pane -t $SESSION_NAME:0.2 -T "Docker Logs litd2"

# Print help message in the top pane
tmux send-keys -t $SESSION_NAME:0.0 "echo 'Press Ctrl+b then d to detach from the tmux session. To end the session, type exit in each pane or use tmux kill-session -t $SESSION_NAME.'" C-m

# Run the demo script in the top pane
tmux send-keys -t $SESSION_NAME:0.0 "bash $DEMO_SCRIPT" C-m

# Run the Docker logs for litd1 in the bottom left pane
tmux send-keys -t $SESSION_NAME:0.1 "docker logs -f taproot-assets-playground-litd1-1" C-m

# Run the Docker logs for litd2 in the bottom right pane
tmux send-keys -t $SESSION_NAME:0.2 "docker logs -f taproot-assets-playground-litd2-1" C-m

# Select the top pane to make it active
tmux select-pane -t $SESSION_NAME:0.0

# Attach to the tmux session
tmux attach-session -t $SESSION_NAME