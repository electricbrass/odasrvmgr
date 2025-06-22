import subprocess

# Start 'tail -f' as a subprocess
with subprocess.Popen(
    ["tail", "-F", "/opt/odasrv/logs/friends.log"],
    stdout=subprocess.PIPE,    # Capture standard output
    stderr=subprocess.PIPE,    # Capture errors
    text=True                  # Decode bytes to str (Python 3.7+)
) as proc:
    if proc.stdout is None:
        raise RuntimeError("Failed to start subprocess or stdout is None")
    # Read lines as they are written to the log
    for line in proc.stdout:
        print(line, end='')  # Process or display each line
        #print(f"LINE: {repr(line)}")
