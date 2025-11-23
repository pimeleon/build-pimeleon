#!/bin/bash
set -euo pipefail

# Generate test report from results

RESULTS_DIR=$1
REPORT_FILE="${RESULTS_DIR}/report.html"

# Generate HTML report
cat > "$REPORT_FILE" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Pimeleon Test Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #007bff;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
        }
        .summary {
            display: flex;
            gap: 20px;
            margin: 20px 0;
        }
        .summary-card {
            flex: 1;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .passed {
            background-color: #d4edda;
            color: #155724;
        }
        .failed {
            background-color: #f8d7da;
            color: #721c24;
        }
        .warning {
            background-color: #fff3cd;
            color: #856404;
        }
        .test-results {
            margin-top: 20px;
        }
        .test-result {
            padding: 10px;
            margin: 5px 0;
            border-radius: 4px;
            border-left: 4px solid;
        }
        .test-pass {
            background-color: #f0f9ff;
            border-color: #28a745;
        }
        .test-fail {
            background-color: #fff5f5;
            border-color: #dc3545;
        }
        .timestamp {
            color: #666;
            font-size: 0.9em;
        }
        pre {
            background-color: #f8f9fa;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Pimeleon Test Report</h1>
        <p class="timestamp">Generated: $(date)</p>
        
        <div class="summary">
            <div class="summary-card passed">
                <h3>Passed</h3>
                <div style="font-size: 2em;">$(grep -c "PASS" "${RESULTS_DIR}"/*.txt 2>/dev/null || echo "0")</div>
            </div>
            <div class="summary-card failed">
                <h3>Failed</h3>
                <div style="font-size: 2em;">$(grep -c "FAIL" "${RESULTS_DIR}"/*.txt 2>/dev/null || echo "0")</div>
            </div>
            <div class="summary-card warning">
                <h3>Warnings</h3>
                <div style="font-size: 2em;">$(grep -c "WARN" "${RESULTS_DIR}"/*.txt 2>/dev/null || echo "0")</div>
            </div>
        </div>
        
        <h2>Test Results</h2>
        <div class="test-results">
EOF

# Add test results
for result_file in "${RESULTS_DIR}"/*.txt; do
    if [[ -f "$result_file" ]]; then
        echo "<h3>$(basename "$result_file" .txt)</h3>" >> "$REPORT_FILE"
        echo "<pre>" >> "$REPORT_FILE"
        cat "$result_file" >> "$REPORT_FILE"
        echo "</pre>" >> "$REPORT_FILE"
    fi
done

# Close HTML
cat >> "$REPORT_FILE" <<'EOF'
        </div>
        
        <h2>System Information</h2>
        <pre>
Host OS: $(uname -a)
Docker Version: $(docker --version)
Build Date: $(date)
        </pre>
    </div>
</body>
</html>
EOF

echo "Test report generated: $REPORT_FILE"