# Arc Commands

Reference for all Arc command-line commands.

## init

Initialize a new Arc project.

```sh
arc init [project-name] [--directory <path>]
```

### Arguments

- `project-name` (optional): Name for the project. Defaults to the current directory name.

### Options

- `--directory`, `-d`: Directory to initialize the project in. Defaults to the current directory.

### Example

```sh
arc init my-project
arc init --directory ~/projects/my-project
```

## start

Start the Arc server.

```sh
arc start [--config <path>] [--background] [--log-file <path>]
```

### Options

- `--config`, `-c`: Path to the configuration file. Defaults to `config.pkl`.
- `--background`: Run the server in background mode.
- `--log-file`: Path to log file (for background mode).

### Example

```sh
arc start
arc start --config custom.pkl --background
```

## stop

Stop running Arc servers.

```sh
arc stop [process-name]
```

### Arguments

- `process-name` (optional): Name of the specific process to stop. If omitted, stops all Arc processes.

### Example

```sh
arc stop
arc stop my-arc-instance
```

## status

Check the status of running Arc servers.

```sh
arc status
```

Displays information about all running Arc processes, including:
- Process name and PID
- Configuration path
- Server status
- Site health status

## logs

View server logs.

```sh
arc logs [process-name] [--follow]
```

### Arguments

- `process-name` (optional): Name of the specific process. If omitted, shows logs for all processes.

### Options

- `--follow`, `-f`: Follow log output (similar to `tail -f`).

### Example

```sh
arc logs
arc logs my-arc-instance --follow
```
