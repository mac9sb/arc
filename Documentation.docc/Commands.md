# Arc Commands

Reference for all Arc command-line commands.

## init

Initialize a new Arc project.

```bash
arc init [project-name] [--directory <path>]
```

### Arguments

- `project-name` (optional): Name for the project. Defaults to the current directory name.

### Options

- `--directory`, `-d`: Directory to initialize the project in. Defaults to the current directory.

### Example

```bash
arc init my-project
arc init --directory ~/projects/my-project
```

## run

Start the Arc server.

```bash
arc run [--config <path>] [--background] [--log-file <path>]
```

### Options

- `--config`, `-c`: Path to the configuration file. Defaults to `pkl/config.pkl`.
- `--background`: Run the server in background mode.
- `--log-file`: Path to log file (for background mode).

### Example

```bash
arc run
arc run --config custom.pkl --background
```

## stop

Stop running Arc servers.

```bash
arc stop [process-name]
```

### Arguments

- `process-name` (optional): Name of the specific process to stop. If omitted, stops all Arc processes.

### Example

```bash
arc stop
arc stop my-arc-instance
```

## status

Check the status of running Arc servers.

```bash
arc status
```

Displays information about all running Arc processes, including:
- Process name and PID
- Configuration path
- Server status
- Site health status

## logs

View server logs.

```bash
arc logs [process-name] [--follow]
```

### Arguments

- `process-name` (optional): Name of the specific process. If omitted, shows logs for all processes.

### Options

- `--follow`, `-f`: Follow log output (similar to `tail -f`).

### Example

```bash
arc logs
arc logs my-arc-instance --follow
```
