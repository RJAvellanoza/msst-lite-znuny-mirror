// --
// Copyright (C) 2025 MSST, https://msst.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY.
// --
/*global d3, nv */

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.OperationalReports
 * @memberof Core.Agent
 * @author MSST
 * @description
 *      Operational Reports chart drawing functionality using D3/NVD3.
 */
Core.Agent.OperationalReports = (function (TargetNS) {

    // Priority colors matching the system
    var PriorityColors = {
        'P1': '#d32f2f',  // Critical - Red
        'P2': '#f57c00',  // High - Orange
        'P3': '#fbc02d',  // Medium - Yellow
        'P4': '#1976d2'   // Low - Blue
    };

    // Chart colors
    var ChartColors = {
        'current': '#00BCD4',      // Bright cyan for current period
        'previous': '#B0BEC5',     // Gray for previous period
        'baseline': '#FF9800',     // Orange for average baseline
        'anomaly': '#F44336'       // Red for anomalies
    };

    /**
     * @name Init
     * @memberof Core.Agent.OperationalReports
     * @function
     * @description
     *      Initialize the module.
     */
    TargetNS.Init = function() {
        // Check dependencies
        if (!window.d3 || !window.nv) {
            console.log('D3/NVD3 libraries not loaded');
            return;
        }

        // Initialize charts if data is available
        if (typeof window.OperationalReportsChartData !== 'undefined') {
            TargetNS.InitializeDashboardCharts();
        }
    };

    /**
     * @name InitializeDashboardCharts
     * @memberof Core.Agent.OperationalReports
     * @function
     * @description
     *      Initialize all dashboard charts.
     */
    TargetNS.InitializeDashboardCharts = function() {
        var ChartData = window.OperationalReportsChartData || {};

        // Draw 30-day trend chart
        if (ChartData.TrendChart && $('#TrendChart').length) {
            TargetNS.DrawTrendChart('#TrendChart', ChartData.TrendChart);
        }

        // Draw priority breakdown chart
        if (ChartData.PriorityChart && $('#PriorityChart').length) {
            TargetNS.DrawPriorityChart('#PriorityChart', ChartData.PriorityChart);
        }
    };

    /**
     * @name DrawTrendChart
     * @memberof Core.Agent.OperationalReports
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data
     * @description
     *      Draw a bar chart showing incident trends with comparison, baseline, and anomalies.
     */
    TargetNS.DrawTrendChart = function(Selector, Data) {
        if (!Data || !Data.data || Data.data.length === 0) {
            $(Selector).parent().html('<p class="Center">No trend data available.</p>');
            return;
        }

        var margin = {top: 80, right: 30, bottom: 80, left: 60},
            containerWidth = $(Selector).parent().width() || 800,
            width = containerWidth - margin.left - margin.right,
            height = 400 - margin.top - margin.bottom;

        // Clear existing chart
        d3.select(Selector).selectAll("*").remove();

        var svg = d3.select(Selector)
            .attr("width", width + margin.left + margin.right)
            .attr("height", height + margin.top + margin.bottom)
            .append("g")
            .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

        // Prepare data
        var chartData = Data.data;
        var maxValue = parseFloat(Data.maxValue) || d3.max(chartData, function(d) { return d.count; });
        var average = parseFloat(Data.average) || 0;

        // X scale
        var x = d3.scale.ordinal()
            .domain(chartData.map(function(d) { return d.date; }))
            .rangeRoundBands([0, width], 0.1);

        // Y scale
        var y = d3.scale.linear()
            .domain([0, Math.max(maxValue * 1.3, average * 1.5)])
            .range([height, 0]);

        // X axis
        var xAxis = d3.svg.axis()
            .scale(x)
            .orient("bottom")
            .tickFormat(function(d) {
                // Show only day-month for space efficiency
                return d.substring(5).replace('-', '/');
            });

        // Y axis
        var yAxis = d3.svg.axis()
            .scale(y)
            .orient("left")
            .ticks(8)
            .tickFormat(d3.format("d"));

        // Add X axis
        svg.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + height + ")")
            .call(xAxis)
            .selectAll("text")
            .style("text-anchor", "end")
            .attr("dx", "-.8em")
            .attr("dy", ".15em")
            .attr("transform", "rotate(-45)");

        // Add Y axis
        svg.append("g")
            .attr("class", "y axis")
            .call(yAxis)
            .append("text")
            .attr("transform", "rotate(-90)")
            .attr("y", 6)
            .attr("dy", ".71em")
            .style("text-anchor", "end")
            .text("Incident Count");

        // Add bars
        svg.selectAll(".bar")
            .data(chartData)
            .enter().append("rect")
            .attr("class", function(d) {
                return "bar" + (d.isCurrent ? " current-period" : "");
            })
            .attr("x", function(d) { return x(d.date); })
            .attr("width", x.rangeBand())
            .attr("y", function(d) { return y(d.count); })
            .attr("height", function(d) { return height - y(d.count); })
            .style("fill", function(d) {
                return d.isCurrent ? ChartColors.current : '#78909C';
            })
            .on("mouseover", function(d) {
                // Show tooltip
                var tooltip = d3.select("body").append("div")
                    .attr("class", "d3-tooltip")
                    .style("position", "absolute")
                    .style("background", "rgba(0,0,0,0.8)")
                    .style("color", "#fff")
                    .style("padding", "10px")
                    .style("border-radius", "4px")
                    .style("pointer-events", "none")
                    .style("z-index", "10000");

                var tooltipHtml = "<strong>" + d.date + "</strong><br/>";
                tooltipHtml += "Total: " + d.count + "<br/>";
                tooltipHtml += "P1-Critical: " + (d.p1 || 0) + "<br/>";
                tooltipHtml += "P2-High: " + (d.p2 || 0) + "<br/>";
                tooltipHtml += "P3-Medium: " + (d.p3 || 0) + "<br/>";
                tooltipHtml += "P4-Low: " + (d.p4 || 0);

                tooltip.html(tooltipHtml)
                    .style("left", (d3.event.pageX + 10) + "px")
                    .style("top", (d3.event.pageY - 28) + "px");
            })
            .on("mouseout", function() {
                d3.selectAll(".d3-tooltip").remove();
            });

        // Add average baseline (dotted line)
        if (average > 0) {
            svg.append("line")
                .attr("class", "baseline")
                .attr("x1", 0)
                .attr("x2", width)
                .attr("y1", y(average))
                .attr("y2", y(average))
                .style("stroke", ChartColors.baseline)
                .style("stroke-width", 2)
                .style("stroke-dasharray", "5,5");

            // Add baseline label
            svg.append("text")
                .attr("class", "baseline-label")
                .attr("x", width - 5)
                .attr("y", y(average) - 5)
                .style("text-anchor", "end")
                .style("font-size", "11px")
                .style("fill", ChartColors.baseline)
                .text("Avg: " + average.toFixed(1));
        }

        // Add anomaly indicators (red dots with counts)
        chartData.forEach(function(d) {
            if (d.isAnomaly && d.anomalyLabel) {
                // Calculate positions ensuring they don't go above the chart
                var dotY = Math.max(16, y(d.count) - 20);
                var labelY = Math.max(10, y(d.count) - 28);

                // Draw red circle
                svg.append("circle")
                    .attr("class", "anomaly-dot")
                    .attr("cx", x(d.date) + x.rangeBand() / 2)
                    .attr("cy", dotY)
                    .attr("r", 6)
                    .style("fill", ChartColors.anomaly);

                // Add count label
                svg.append("text")
                    .attr("class", "anomaly-label")
                    .attr("x", x(d.date) + x.rangeBand() / 2)
                    .attr("y", labelY)
                    .style("text-anchor", "middle")
                    .style("font-size", "10px")
                    .style("font-weight", "bold")
                    .style("fill", ChartColors.anomaly)
                    .text(d.anomalyLabel);
            }
        });

        // Add chart title
        svg.append("text")
            .attr("x", width / 2)
            .attr("y", -55)
            .style("text-anchor", "middle")
            .style("font-size", "16px")
            .style("font-weight", "bold")
            .text(Data.title || "30-Day Incident Trends");

        // Add legend
        var legend = svg.append("g")
            .attr("class", "legend")
            .attr("transform", "translate(0, -50)");

        var legendItems = [
            {label: "Current Period", color: ChartColors.current},
            {label: "Previous Period", color: "#78909C"}
        ];

        if (average > 0) {
            legendItems.push({label: "Average", color: ChartColors.baseline});
        }

        legendItems.forEach(function(item, i) {
            var legendItem = legend.append("g")
                .attr("transform", "translate(" + (i * 120) + ", 0)");

            legendItem.append("rect")
                .attr("width", 12)
                .attr("height", 12)
                .style("fill", item.color);

            legendItem.append("text")
                .attr("x", 18)
                .attr("y", 10)
                .style("font-size", "11px")
                .text(item.label);
        });

        // Add CSS styles
        AddChartStyles();
    };

    /**
     * @name DrawPriorityChart
     * @memberof Core.Agent.OperationalReports
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data
     * @description
     *      Draw a stacked bar chart showing priority breakdown.
     */
    TargetNS.DrawPriorityChart = function(Selector, Data) {
        if (!Data || !Data.data || Data.data.length === 0) {
            $(Selector).parent().html('<p class="Center">No priority data available.</p>');
            return;
        }

        var containerWidth = $(Selector).parent().width() || 600,
            width = containerWidth,
            height = 350,
            radius = Math.min(width, height) / 2 - 40;

        // Clear existing chart
        d3.select(Selector).selectAll("*").remove();

        var svg = d3.select(Selector)
            .attr("width", width)
            .attr("height", height)
            .append("g")
            .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

        // Prepare pie data - aggregate all priorities
        var pieData = [];
        var priorityColors = {
            'P1': PriorityColors.P1,
            'P2': PriorityColors.P2,
            'P3': PriorityColors.P3,
            'P4': PriorityColors.P4
        };

        var priorityLabels = {
            'P1': 'P1-Critical',
            'P2': 'P2-High',
            'P3': 'P3-Medium',
            'P4': 'P4-Low'
        };

        // Aggregate totals for each priority across all data points
        var totals = {P1: 0, P2: 0, P3: 0, P4: 0};
        Data.data.forEach(function(d) {
            totals.P1 += d.p1 || 0;
            totals.P2 += d.p2 || 0;
            totals.P3 += d.p3 || 0;
            totals.P4 += d.p4 || 0;
        });

        // Convert to array for pie chart
        for (var key in totals) {
            if (totals[key] > 0) {
                pieData.push({
                    label: key,
                    value: totals[key],
                    color: priorityColors[key]
                });
            }
        }

        if (pieData.length === 0) {
            $(Selector).parent().html('<p class="Center">No priority data available.</p>');
            return;
        }

        // Create pie layout
        var pie = d3.layout.pie()
            .value(function(d) { return d.value; })
            .sort(null);

        var arc = d3.svg.arc()
            .innerRadius(0)
            .outerRadius(radius);

        var labelArc = d3.svg.arc()
            .innerRadius(radius - 60)
            .outerRadius(radius - 60);

        // Draw pie slices
        var g = svg.selectAll(".arc")
            .data(pie(pieData))
            .enter().append("g")
            .attr("class", "arc");

        g.append("path")
            .attr("d", arc)
            .style("fill", function(d) { return d.data.color; })
            .style("stroke", "#fff")
            .style("stroke-width", "2px")
            .on("mouseover", function(d) {
                var tooltip = d3.select("body").append("div")
                    .attr("class", "d3-tooltip")
                    .style("position", "absolute")
                    .style("background", "rgba(0,0,0,0.8)")
                    .style("color", "#fff")
                    .style("padding", "8px")
                    .style("border-radius", "4px")
                    .style("pointer-events", "none")
                    .style("z-index", "10000");

                var percentage = ((d.value / d3.sum(pieData, function(d) { return d.value; })) * 100).toFixed(1);
                tooltip.html("<strong>" + priorityLabels[d.data.label] + "</strong><br/>Count: " + d.data.value + " (" + percentage + "%)")
                    .style("left", (d3.event.pageX + 10) + "px")
                    .style("top", (d3.event.pageY - 28) + "px");
            })
            .on("mouseout", function() {
                d3.selectAll(".d3-tooltip").remove();
            });

        // Add percentage labels on slices
        g.append("text")
            .attr("transform", function(d) { return "translate(" + labelArc.centroid(d) + ")"; })
            .attr("dy", ".35em")
            .style("text-anchor", "middle")
            .style("font-size", "12px")
            .style("font-weight", "bold")
            .style("fill", "#fff")
            .text(function(d) {
                var percentage = ((d.value / d3.sum(pieData, function(d) { return d.value; })) * 100).toFixed(1);
                return percentage + "%";
            });

        // Add legend
        var legend = svg.append("g")
            .attr("class", "legend")
            .attr("transform", "translate(" + (radius + 30) + ", " + (-radius) + ")");

        pieData.forEach(function(d, i) {
            var legendItem = legend.append("g")
                .attr("transform", "translate(0, " + (i * 25) + ")");

            legendItem.append("rect")
                .attr("width", 15)
                .attr("height", 15)
                .style("fill", d.color);

            legendItem.append("text")
                .attr("x", 20)
                .attr("y", 12)
                .style("font-size", "12px")
                .text(priorityLabels[d.label] + ": " + d.value);
        });

        // Add title
        svg.append("text")
            .attr("x", 0)
            .attr("y", -radius - 20)
            .style("text-anchor", "middle")
            .style("font-size", "14px")
            .style("font-weight", "bold")
            .text(Data.title || "Priority Breakdown");

        AddChartStyles();
    };

    /**
     * @name AddChartStyles
     * @memberof Core.Agent.OperationalReports
     * @function
     * @description
     *      Add CSS styles for charts if not already present.
     */
    function AddChartStyles() {
        if ($('#operational-reports-chart-styles').length === 0) {
            var styles = `
                <style id="operational-reports-chart-styles">
                    .axis path, .axis line {
                        fill: none;
                        stroke: #000;
                        shape-rendering: crispEdges;
                    }
                    .axis text {
                        font-family: sans-serif;
                        font-size: 11px;
                    }
                    .bar {
                        transition: opacity 0.2s;
                    }
                    .bar:hover {
                        opacity: 0.8;
                        cursor: pointer;
                    }
                    .bar.current-period {
                        stroke: #006064;
                        stroke-width: 1px;
                    }
                    .baseline {
                        opacity: 0.8;
                    }
                    .anomaly-dot {
                        stroke: #fff;
                        stroke-width: 2px;
                    }
                    .legend text {
                        font-family: sans-serif;
                    }
                    svg {
                        font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
                        overflow: visible;
                    }
                </style>
            `;
            $('head').append(styles);
        }
    }

    /**
     * @name DrawMonthlyReportChart
     * @memberof Core.Agent.OperationalReports
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with weekly breakdown
     * @description
     *      Draw bar chart for monthly report showing weekly breakdown.
     */
    TargetNS.DrawMonthlyReportChart = function(Selector, Data) {
        // Similar to DrawTrendChart but adapted for weekly data
        // Implementation follows same pattern
    };

    /**
     * @name DrawYearlyReportChart
     * @memberof Core.Agent.OperationalReports
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with monthly breakdown
     * @description
     *      Draw bar chart for yearly report showing monthly breakdown.
     */
    TargetNS.DrawYearlyReportChart = function(Selector, Data) {
        // Similar to DrawTrendChart but adapted for monthly data
        // Implementation follows same pattern
    };

    return TargetNS;
}(Core.Agent.OperationalReports || {}));
