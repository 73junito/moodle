<?php
// generate_lab.php
// Simple CLI wrapper for mod/virtualgarage to invoke the centralized trigger helper.
// Usage (PowerShell recommended):
// 1) Pipe prompt via STDIN (preferred to avoid quoting issues):
//    @"\nYour prompt here\n"@ | & 'D:\Moodle\server\php\php.exe' 'D:\Moodle\mod\virtualgarage\generate_lab.php' --model='qwen3-vl:8b' --out='D:\Moodle\server\moodle\local\ollama_generated\vg_generated.json' --verbose
// 2) Or inline prompt (PowerShell single quotes):
//    & 'D:\Moodle\server\php\php.exe' 'D:\Moodle\mod\virtualgarage\generate_lab.php' --model='qwen3-vl:8b' --out='D:\Moodle\server\moodle\local\ollama_generated\vg_generated.json' --prompt='Your prompt here' --verbose

$argvCopy = $argv;
array_shift($argvCopy); // script name

// default paths
$phpbin = 'D:\\Moodle\\server\\php\\php.exe';
$trigger = 'D:\\Moodle\\server\\moodle\\local\\ollama_generated\\trigger_plugin_generation.php';

// parse args (very small parser)
$options = [
    'prompt' => null,
    'out' => null,
    'model' => null,
    'verbose' => false,
];
for ($i = 0; $i < count($argvCopy); $i++) {
    $a = $argvCopy[$i];
    if (strpos($a, '--prompt=') === 0) {
        $options['prompt'] = substr($a, strlen('--prompt='));
    } elseif ($a === '--prompt' && isset($argvCopy[$i+1])) {
        $options['prompt'] = $argvCopy[++$i];
    } elseif (strpos($a, '--out=') === 0) {
        $options['out'] = substr($a, strlen('--out='));
    } elseif ($a === '--out' && isset($argvCopy[$i+1])) {
        $options['out'] = $argvCopy[++$i];
    } elseif (strpos($a, '--model=') === 0) {
        $options['model'] = substr($a, strlen('--model='));
    } elseif ($a === '--model' && isset($argvCopy[$i+1])) {
        $options['model'] = $argvCopy[++$i];
    } elseif ($a === '--verbose' || $a === '-v') {
        $options['verbose'] = true;
    }
}

// Build command safely for Windows PowerShell usage: wrap args with single quotes
$cmdParts = [];
$cmdParts[] = "& '" . $phpbin . "' '" . $trigger . "'";
if (!empty($options['model'])) {
    $cmdParts[] = "--model='" . str_replace("'", "''", $options['model']) . "'";
}
if (!empty($options['out'])) {
    $cmdParts[] = "--out='" . str_replace("'", "''", $options['out']) . "'";
}
if (!empty($options['prompt'])) {
    $cmdParts[] = "--prompt='" . str_replace("'", "''", $options['prompt']) . "'";
}
if (!empty($options['verbose'])) {
    $cmdParts[] = "--verbose";
}

$fullCmd = implode(' ', $cmdParts);

// If no prompt provided via CLI, we will read STDIN and pipe it to the trigger script.
$stdin = '';
$stdinStream = fopen('php://stdin', 'r');
if ($stdinStream !== false) {
    stream_set_blocking($stdinStream, false);
    $stdin = stream_get_contents($stdinStream);
    fclose($stdinStream);
    $stdin = trim((string)$stdin);
}

if ($stdin !== '' && strpos($fullCmd, '--prompt=') === false) {
    // Use shell to echo the stdin and pipe into the trigger command
    // Use PowerShell -Command to preserve quoting on Windows if available
    $tmp = preg_replace("/^& \\\'(.*)\\\' \\\'(.*)\\\'/", "& '$phpbin' '$trigger'", $fullCmd);
    // Build a command that echoes the stdin and pipes into the php call
    // Use cmd.exe echo with delayed expansion could be messy; instead write stdin to a temp file and pass via type
    $tmpfile = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'vg_prompt_' . uniqid() . '.txt';
    file_put_contents($tmpfile, $stdin);
    // Construct command using PowerShell to get-content and pipe
    $psCmd = "Get-Content -Raw -LiteralPath '" . $tmpfile . "' | " . $fullCmd;
    if ($options['verbose']) {
        echo "Running (PowerShell): \n" . $psCmd . "\n";
    }
    // Execute via PowerShell
    $out = shell_exec("powershell -NoProfile -Command \"$psCmd\" 2>&1");
    echo $out;
    @unlink($tmpfile);
    exit(0);
} else {
    // No piped stdin; run the command as-is
    if ($options['verbose']) {
        echo "Running: " . $fullCmd . "\n";
    }
    $out = shell_exec($fullCmd . ' 2>&1');
    echo $out;
    exit(0);
}
