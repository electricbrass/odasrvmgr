tmux new-session \; \
  split-window -vb \; \
  resize-pane -D 100 \; \
  send-keys "tail -f /opt/odasrv/logs/${1}.log" C-m \; \
  select-pane -D \; \
  send-keys "while true; do read -e -p '> ' cmd && echo \"\$cmd\" >> /opt/odasrv/con/${1}; done" C-m
