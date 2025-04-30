#!/bin/bash
set -e

# Create directories
mkdir -p /data/silesia /results

# Download and extract the Silesia corpus
echo "Downloading Silesia corpus..."
cd /data
wget -q http://sun.aei.polsl.pl/~sdeor/corpus/silesia.zip
unzip -q silesia.zip -d silesia
rm silesia.zip

# Initialize results file with headers
RESULTS_FILE="/results/compression_results.csv"
echo "File,Algorithm,Original Size (KB),Compressed Size (KB),Compression Ratio,Compression Time (s),Decompression Time (s),Compression Speed (MB/s),Decompression Speed (MB/s)" >"$RESULTS_FILE"

# Function to test compression algorithm
test_compression() {
    local file=$1
    local algorithm=$2
    local command=$3
    local decompress_command=$4
    local extension=$5

    local filename=$(basename "$file")
    local original_size=$(du -k "$file" | cut -f1)
    local original_size_bytes=$(stat -c %s "$file")
    local original_mb=$(echo "scale=3; $original_size_bytes / 1048576" | bc)

    echo "Testing $algorithm on $filename..."

    # Compression test
    local compressed_file="/data/compressed/${filename}${extension}"
    local start_time=$(date +%s.%N)
    eval "$command \"$file\" > \"$compressed_file\""
    local end_time=$(date +%s.%N)
    local compression_time=$(echo "$end_time - $start_time" | bc)
    local compressed_size=$(du -k "$compressed_file" | cut -f1)
    local compression_ratio=$(echo "scale=2; $original_size / $compressed_size" | bc)
    local compression_speed=$(echo "scale=2; $original_mb / $compression_time" | bc)

    # Decompression test
    local decompressed_file="/data/decompressed/${filename}"
    local start_time=$(date +%s.%N)
    eval "$decompress_command \"$compressed_file\" > \"$decompressed_file\""
    local end_time=$(date +%s.%N)
    local decompression_time=$(echo "$end_time - $start_time" | bc)
    local decompression_speed=$(echo "scale=2; $original_mb / $decompression_time" | bc)

    # Verify decompression was successful
    local file_hash=$(md5sum "$file" | cut -d' ' -f1)
    local decompressed_hash=$(md5sum "$decompressed_file" | cut -d' ' -f1)

    if [ "$file_hash" != "$decompressed_hash" ]; then
        echo "WARNING: Decompression verification failed for $filename with $algorithm!" >&2
    fi

    # Log results
    echo "$filename,$algorithm,$original_size,$compressed_size,$compression_ratio,$compression_time,$decompression_time,$compression_speed,$decompression_speed" >>"$RESULTS_FILE"
}

# Create output directories
mkdir -p /data/compressed /data/decompressed

# Run tests for each file in the corpus with each algorithm
find /data/silesia -type f -size +0 | while read file; do
    # Test gzip with different compression levels
    for level in 1 6 9; do
        test_compression "$file" "gzip-$level" "gzip -c -$level" "gzip -d -c" ".gz"
    done

    # Test bzip2 with different compression levels
    for level in 1 5 9; do
        test_compression "$file" "bzip2-$level" "bzip2 -c -$level" "bzip2 -d -c" ".bz2"
    done

    # Test xz with different compression levels
    for level in 1 6 9; do
        test_compression "$file" "xz-$level" "xz -c -$level" "xz -d -c" ".xz"
    done

    # Test zstd with different compression levels
    for level in 1 10 19; do
        test_compression "$file" "zstd-$level" "zstd -c -$level" "zstd -d -c" ".zst"
    done
done

# Generate summary statistics
echo -e "\nGenerating summary statistics..."
echo -e "\nAverage metrics by algorithm:" >>"$RESULTS_FILE"
echo "Algorithm,Avg Compression Ratio,Avg Compression Time (s),Avg Decompression Time (s),Avg Compression Speed (MB/s),Avg Decompression Speed (MB/s)" >>"$RESULTS_FILE"

# Use awk to calculate averages by algorithm
awk -F, 'NR>1 && $2 != "Algorithm" && $2 !~ /^Avg/ {
    count[$2]++;
    if ($5 != "" && $5 != "N/A") ratio_sum[$2] += $5;
    if ($6 != "" && $6 != "N/A") comp_time_sum[$2] += $6;
    if ($7 != "" && $7 != "N/A") decomp_time_sum[$2] += $7;
    if ($8 != "" && $8 != "N/A") comp_speed_sum[$2] += $8;
    if ($9 != "" && $9 != "N/A") decomp_speed_sum[$2] += $9;
}
END {
    for (algo in count) {
        if (count[algo] > 0) {
            printf "%s,%.2f,%.2f,%.2f,%.2f,%.2f\n",
                algo,
                (ratio_sum[algo] ? ratio_sum[algo]/count[algo] : 0),
                (comp_time_sum[algo] ? comp_time_sum[algo]/count[algo] : 0),
                (decomp_time_sum[algo] ? decomp_time_sum[algo]/count[algo] : 0),
                (comp_speed_sum[algo] ? comp_speed_sum[algo]/count[algo] : 0),
                (decomp_speed_sum[algo] ? decomp_speed_sum[algo]/count[algo] : 0);
        }
    }
}' "$RESULTS_FILE" | sort -t, -k2nr >>"$RESULTS_FILE"

# Create a consolidated results file with the total size of all files
echo -e "\nGenerating consolidated results..."
echo "Algorithm,Total Original Size (KB),Total Compressed Size (KB),Overall Compression Ratio" >>"$RESULTS_FILE"

# Use awk to calculate total sizes and overall ratios
awk -F, '
BEGIN {
    PROCINFO["sorted_in"] = "@val_num_desc";
}
NR>1 && $2 != "Algorithm" && $2 !~ /^Avg/ {
    orig_size[$2] += $3;
    comp_size[$2] += $4;
}
END {
    for (algo in orig_size) {
        if (comp_size[algo] > 0) {
            ratio = orig_size[algo]/comp_size[algo];
            printf "%s,%d,%d,%.2f\n",
                algo,
                orig_size[algo],
                comp_size[algo],
                ratio;
        } else {
            printf "%s,%d,%d,N/A\n",
                algo,
                orig_size[algo],
                comp_size[algo];
        }
    }
}' "$RESULTS_FILE" | sort -t, -k4r >>"$RESULTS_FILE" 2>/dev/null || {
    # Fallback sorting that avoids numeric sorting issues
    awk -F, '
    BEGIN {
        PROCINFO["sorted_in"] = "@val_num_desc";
    }
    NR>1 && $2 != "Algorithm" && $2 !~ /^Avg/ {
        orig_size[$2] += $3;
        comp_size[$2] += $4;
    }
    END {
        # Sort by ratio
        for (algo in orig_size) {
            if (comp_size[algo] > 0) {
                ratio = orig_size[algo]/comp_size[algo];
                data[algo] = ratio;
            } else {
                data[algo] = 0;
            }
        }

        # Print in descending order
        PROCINFO["sorted_in"] = "@val_num_desc";
        for (algo in data) {
            if (comp_size[algo] > 0) {
                printf "%s,%d,%d,%.2f\n",
                    algo,
                    orig_size[algo],
                    comp_size[algo],
                    orig_size[algo]/comp_size[algo];
            } else {
                printf "%s,%d,%d,N/A\n",
                    algo,
                    orig_size[algo],
                    comp_size[algo];
            }
        }
    }' "$RESULTS_FILE" >>"$RESULTS_FILE"
}

# Generate a visual report
echo -e "\nCreating a visual report in HTML format..."
cat >"/results/report.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Compression Benchmark Results</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f9f9f9;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
        }
        .container {
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 20px;
            margin-bottom: 20px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #f2f2f2;
            position: sticky;
            top: 0;
            z-index: 10;
            border-bottom: 2px solid #ddd;
        }
        tr:hover { background-color: #f5f5f5; }
        tr.selected { background-color: #e3f2fd !important; }

        .chart-container {
            height: 400px;
            margin-bottom: 30px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            padding: 15px;
        }
        h1 {
            color: #2c3e50;
            margin-top: 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #eee;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            padding-bottom: 8px;
            border-bottom: 1px solid #eee;
        }

        /* Tab styling */
        .tabs {
            display: flex;
            border-bottom: 1px solid #ddd;
            margin-bottom: 20px;
        }
        .tab {
            padding: 10px 20px;
            cursor: pointer;
            border: 1px solid transparent;
            border-bottom: none;
            border-radius: 4px 4px 0 0;
            margin-right: 5px;
            background-color: #f8f8f8;
        }
        .tab:hover {
            background-color: #e9e9e9;
        }
        .tab.active {
            background-color: white;
            border-color: #ddd;
            border-bottom: 2px solid white;
            margin-bottom: -1px;
            font-weight: bold;
        }
        .tab-content {
            display: none;
            padding: 15px 0;
        }
        .tab-content.active {
            display: block;
        }

        #tableSearch {
            padding: 10px;
            margin-bottom: 15px;
            width: 300px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }

        .summary {
            background-color: #f8f9fa;
            padding: 15px;
            border-left: 4px solid #4caf50;
            margin-bottom: 20px;
            border-radius: 0 4px 4px 0;
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <h1>Compression Algorithm Benchmark Results</h1>
        <p>Benchmark run on: <span id="currentDate">Loading date...</span></p>

        <div class="summary">
            <p><strong>Benchmark Summary:</strong> This report compares performance of xz, gzip, bzip2, and zstd compression algorithms on the Silesia corpus.</p>
        </div>

        <div class="tabs">
            <div class="tab active" onclick="switchTab('chartTab')">Charts</div>
            <div class="tab" onclick="switchTab('detailsTab')">Detailed Results</div>
            <div class="tab" onclick="switchTab('summaryTab')">Summary</div>
        </div>

        <div id="chartTab" class="tab-content active">
            <h2>Performance Charts</h2>
            <div class="chart-container">
                <canvas id="ratioChart"></canvas>
            </div>
            <div class="chart-container">
                <canvas id="timeChart"></canvas>
            </div>
            <div class="chart-container">
                <canvas id="speedChart"></canvas>
            </div>
        </div>

        <div id="detailsTab" class="tab-content">
            <h2>Detailed Results</h2>
            <input type="text" id="tableSearch" placeholder="Search files or algorithms..." onkeyup="filterTable()">
            <table id="resultsTable">
                <thead>
                    <tr>
                        <th>File</th>
                        <th>Algorithm</th>
                        <th>Original Size (KB)</th>
                        <th>Compressed Size (KB)</th>
                        <th>Compression Ratio</th>
                        <th>Compression Time (s)</th>
                        <th>Decompression Time (s)</th>
                        <th>Compression Speed (MB/s)</th>
                        <th>Decompression Speed (MB/s)</th>
                    </tr>
                </thead>
                <tbody>
EOF

# Add table rows from the CSV file (skip headers and summary sections)
awk -F, 'NR>1 && $2 != "Algorithm" && $2 !~ /^Avg/ && NF==9 {
    print "<tr>";
    for(i=1; i<=NF; i++) {
        print "<td>" $i "</td>";
    }
    print "</tr>";
}' "$RESULTS_FILE" >>"/results/report.html"

cat >>"/results/report.html" <<'EOF'
                </tbody>
            </table>
        </div>

        <div id="summaryTab" class="tab-content">
            <h2>Average Metrics by Algorithm</h2>
            <table>
                <thead>
                    <tr>
                        <th>Algorithm</th>
                        <th>Avg Compression Ratio</th>
                        <th>Avg Compression Time (s)</th>
                        <th>Avg Decompression Time (s)</th>
                        <th>Avg Compression Speed (MB/s)</th>
                        <th>Avg Decompression Speed (MB/s)</th>
                    </tr>
                </thead>
                <tbody>
EOF

# Generate summary rows dynamically
echo "Generating summary rows for HTML report..."
awk -F, 'NR>1 && $2 != "Algorithm" && $2 !~ /^Avg/ && $2 ~ /-[0-9]+$/ {
    count[$2]++;
    orig_sum[$2] += $3;
    comp_sum[$2] += $4;
    ratio_sum[$2] += $5;
    comp_time_sum[$2] += $6;
    decomp_time_sum[$2] += $7;
    comp_speed_sum[$2] += $8;
    decomp_speed_sum[$2] += $9;
}
END {
    for (algo in count) {
        if (count[algo] > 0) {
            print "<tr>";
            print "<td>" algo "</td>";
            printf "<td>%.2f</td>", ratio_sum[algo]/count[algo];
            printf "<td>%.2f</td>", comp_time_sum[algo]/count[algo];
            printf "<td>%.2f</td>", decomp_time_sum[algo]/count[algo];
            printf "<td>%.2f</td>", comp_speed_sum[algo]/count[algo];
            printf "<td>%.2f</td>", decomp_speed_sum[algo]/count[algo];
            print "</tr>";
        }
    }
}' "$RESULTS_FILE" >>"/results/report.html"

cat >>"/results/report.html" <<'EOF'
                </tbody>
            </table>
        </div>
    </div>

    <script>
        // Set the current date
        document.getElementById('currentDate').textContent = new Date().toLocaleString();

        // Tab switching functionality
        function switchTab(tabId) {
            // Hide all tabs
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });

            // Show selected tab
            document.getElementById(tabId).classList.add('active');
            Array.from(document.querySelectorAll('.tab')).find(
                tab => tab.textContent.includes(tabId.replace('Tab', ''))
            ).classList.add('active');
        }

        // Table search functionality
        function filterTable() {
            const input = document.getElementById('tableSearch');
            const filter = input.value.toUpperCase();
            const table = document.getElementById('resultsTable');
            const rows = table.getElementsByTagName('tr');

            for (let i = 1; i < rows.length; i++) {
                let visible = false;
                const cells = rows[i].getElementsByTagName('td');

                for (let j = 0; j < 2; j++) { // Only search in file and algorithm columns
                    const cell = cells[j];
                    if (cell) {
                        const text = cell.textContent || cell.innerText;
                        if (text.toUpperCase().indexOf(filter) > -1) {
                            visible = true;
                            break;
                        }
                    }
                }

                rows[i].style.display = visible ? '' : 'none';
            }
        }

        // Add event handlers to highlight table rows on hover or click
        document.querySelectorAll('#resultsTable tbody tr').forEach(row => {
            row.addEventListener('mouseover', function() {
                this.style.backgroundColor = '#f0f0f0';
            });
            row.addEventListener('mouseout', function() {
                this.style.backgroundColor = '';
            });
            row.addEventListener('click', function() {
                // Toggle a 'selected' class
                if (this.classList.contains('selected')) {
                    this.classList.remove('selected');
                    this.style.backgroundColor = '';
                } else {
                    document.querySelectorAll('#resultsTable tbody tr').forEach(r => {
                        r.classList.remove('selected');
                        r.style.backgroundColor = '';
                    });
                    this.classList.add('selected');
                    this.style.backgroundColor = '#e3f2fd';
                }
            });
        });

        // We'll read the CSV data directly from the table in the DOM
        function extractDataFromTable() {
            const table = document.getElementById('resultsTable');
            if (!table) {
                console.error('Results table not found');
                return [];
            }

            const rows = table.querySelectorAll('tbody tr');
            const data = {};

            // Group data by algorithm
            Array.from(rows).forEach(row => {
                const cells = row.querySelectorAll('td');
                if (cells.length >= 9) {
                    const algorithm = cells[1].textContent;
                    if (!data[algorithm]) {
                        data[algorithm] = {
                            count: 0,
                            ratioSum: 0,
                            compTimeSum: 0,
                            decompTimeSum: 0,
                            compSpeedSum: 0,
                            decompSpeedSum: 0
                        };
                    }

                    data[algorithm].count++;
                    data[algorithm].ratioSum += parseFloat(cells[4].textContent) || 0;
                    data[algorithm].compTimeSum += parseFloat(cells[5].textContent) || 0;
                    data[algorithm].decompTimeSum += parseFloat(cells[6].textContent) || 0;
                    data[algorithm].compSpeedSum += parseFloat(cells[7].textContent) || 0;
                    data[algorithm].decompSpeedSum += parseFloat(cells[8].textContent) || 0;
                }
            });

            // Calculate averages
            const avgData = Object.keys(data).map(algorithm => {
                const item = data[algorithm];
                if (item.count === 0) return null;

                return {
                    algorithm: algorithm,
                    ratio: item.ratioSum / item.count,
                    compTime: item.compTimeSum / item.count,
                    decompTime: item.decompTimeSum / item.count,
                    compSpeed: item.compSpeedSum / item.count,
                    decompSpeed: item.decompSpeedSum / item.count
                };
            }).filter(item => item !== null);

            return avgData;
        }

        const avgData = extractDataFromTable();

        // Ensure we have data
        if (avgData.length === 0) {
            console.error('No data extracted from table');
            document.body.innerHTML += '<div class="summary">Error: No data available for charts</div>';
        } else {
            // Sort algorithms by compression method and level
            const algorithms = [...new Set(avgData.map(d => d.algorithm))].sort((a, b) => {
                const [aMethod, aLevel] = a.split('-');
                const [bMethod, bLevel] = b.split('-');
                if (aMethod === bMethod) {
                    return parseInt(aLevel) - parseInt(bLevel);
                }
                return aMethod.localeCompare(bMethod);
            });

            // Create color map for algorithms
            const colorMap = {
                'gzip': 'rgba(75, 192, 192, 1)',
                'bzip2': 'rgba(255, 99, 132, 1)',
                'xz': 'rgba(54, 162, 235, 1)',
                'zstd': 'rgba(255, 159, 64, 1)'
            };

            // Get colors for each algorithm
            const getColor = (algorithm) => {
                const method = algorithm.split('-')[0];
                return colorMap[method] || 'rgba(128, 128, 128, 1)';
            };

            // Get background colors with transparency
            const getBackgroundColor = (algorithm, alpha = 0.7) => {
                const baseColor = getColor(algorithm);
                return baseColor.replace(/[0-9.]+\)$/, alpha + ')');
            };

            // Create ratio chart
            new Chart(document.getElementById('ratioChart').getContext('2d'), {
                type: 'bar',
                data: {
                    labels: algorithms,
                    datasets: [{
                        label: 'Compression Ratio (higher is better)',
                        data: algorithms.map(algo => avgData.find(d => d.algorithm === algo).ratio),
                        backgroundColor: algorithms.map(algo => getBackgroundColor(algo, 0.7))
                    }]
                },
                options: {
                    indexAxis: 'y',
                    scales: {
                        x: {
                            beginAtZero: true,
                            title: {
                                display: true,
                                text: 'Ratio (original/compressed)'
                            }
                        }
                    }
                }
            });

            // Create time chart
            new Chart(document.getElementById('timeChart').getContext('2d'), {
                type: 'bar',
                data: {
                    labels: algorithms,
                    datasets: [
                        {
                            label: 'Compression Time (s)',
                            data: algorithms.map(algo => avgData.find(d => d.algorithm === algo).compTime),
                            backgroundColor: algorithms.map(algo => getBackgroundColor(algo, 0.7))
                        },
                        {
                            label: 'Decompression Time (s)',
                            data: algorithms.map(algo => avgData.find(d => d.algorithm === algo).decompTime),
                            backgroundColor: algorithms.map(algo => getBackgroundColor(algo, 0.3))
                        }
                    ]
                },
                options: {
                    indexAxis: 'y',
                    scales: {
                        x: {
                            beginAtZero: true,
                            title: {
                                display: true,
                                text: 'Time (seconds, lower is better)'
                            }
                        }
                    }
                }
            });

            // Create speed chart
            new Chart(document.getElementById('speedChart').getContext('2d'), {
                type: 'bar',
                data: {
                    labels: algorithms,
                    datasets: [
                        {
                            label: 'Compression Speed (MB/s)',
                            data: algorithms.map(algo => avgData.find(d => d.algorithm === algo).compSpeed),
                            backgroundColor: algorithms.map(algo => getBackgroundColor(algo, 0.7))
                        },
                        {
                            label: 'Decompression Speed (MB/s)',
                            data: algorithms.map(algo => avgData.find(d => d.algorithm === algo).decompSpeed),
                            backgroundColor: algorithms.map(algo => getBackgroundColor(algo, 0.3))
                        }
                    ]
                },
                options: {
                    indexAxis: 'y',
                    scales: {
                        x: {
                            beginAtZero: true,
                            title: {
                                display: true,
                                text: 'Speed (MB/s, higher is better)'
                            }
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>
EOF

echo "Benchmark completed successfully!"
echo "Results are available in $RESULTS_FILE"
echo "HTML report is available at /results/report.html"
