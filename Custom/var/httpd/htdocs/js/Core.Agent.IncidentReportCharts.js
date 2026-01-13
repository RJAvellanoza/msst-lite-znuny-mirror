// --
// Copyright (C) 2025 MSST Lite
// --
// This software comes with ABSOLUTELY NO WARRANTY.
// --
/*global d3, nv */

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.IncidentReportCharts
 * @memberof Core.Agent
 * @author MSST Lite
 * @description
 *      Incident Report chart drawing functionality using D3/NVD3.
 */
Core.Agent.IncidentReportCharts = (function (TargetNS) {

    // Priority colors matching the system
    var PriorityColors = {
        'P1': '#d32f2f',  // Critical - Red
        'P2': '#f57c00',  // High - Orange
        'P3': '#fbc02d',  // Medium - Yellow
        'P4': '#1976d2'   // Low - Blue
    };

    // Source colors
    var SourceColors = {
        'Event Monitoring': '#4CAF50',  // Green
        'Manual': '#2196F3'             // Blue
    };

    /**
     * @name Init
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @description
     *      Initialize the module.
     */
    TargetNS.Init = function() {
        console.log('[IncidentReportCharts] Init called');

        // Check dependencies
        if (!window.d3 || !window.nv) {
            console.log('[IncidentReportCharts] D3/NVD3 libraries not loaded');
            return;
        }

        console.log('[IncidentReportCharts] D3/NVD3 loaded successfully');

        // Initialize charts if data is available
        if (typeof window.IncidentReportChartData !== 'undefined') {
            console.log('[IncidentReportCharts] Chart data found:', window.IncidentReportChartData);
            TargetNS.InitializeAllCharts();
        } else {
            console.log('[IncidentReportCharts] No chart data available');
        }
    };

    /**
     * @name InitializeAllCharts
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @description
     *      Initialize all incident report charts.
     */
    TargetNS.InitializeAllCharts = function() {
        var ChartData = window.IncidentReportChartData || {};

        // Draw trend chart
        if (ChartData.TrendChart && $('#TrendChart').length) {
            TargetNS.DrawTrendChart('#TrendChart', ChartData.TrendChart);
        }

        // Draw source distribution chart
        if (ChartData.SourceChart && $('#SourceChart').length) {
            TargetNS.DrawSourceChart('#SourceChart', ChartData.SourceChart);
        }

        // Draw state distribution chart
        if (ChartData.StateChart && $('#StateChart').length) {
            TargetNS.DrawStateChart('#StateChart', ChartData.StateChart);
        }

        // Draw top devices chart
        if (ChartData.TopDevicesChart && $('#TopDevicesChart').length) {
            TargetNS.DrawTopDevicesChart('#TopDevicesChart', ChartData.TopDevicesChart);
        }

        // Draw resolution time histogram
        if (ChartData.ResolutionTimeChart && $('#ResolutionTimeChart').length) {
            TargetNS.DrawResolutionTimeChart('#ResolutionTimeChart', ChartData.ResolutionTimeChart);
        }
    };

    /**
     * @name DrawTrendChart
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with Labels, Series (P1-P4), and Total
     * @description
     *      Draw a multi-line chart showing incident volume trends by priority.
     */
    TargetNS.DrawTrendChart = function(Selector, Data) {
        if (!Data || !Data.Labels || Data.Labels.length === 0) {
            $(Selector).parent().html('<p class="Center">No trend data available.</p>');
            return;
        }

        // Prepare data for NVD3 multibar chart
        var chartData = [
            {
                key: 'P1 - Critical',
                color: PriorityColors.P1,
                values: Data.Labels.map(function(label, i) {
                    return { x: label, y: Data.Series.P1[i] || 0 };
                })
            },
            {
                key: 'P2 - High',
                color: PriorityColors.P2,
                values: Data.Labels.map(function(label, i) {
                    return { x: label, y: Data.Series.P2[i] || 0 };
                })
            },
            {
                key: 'P3 - Medium',
                color: PriorityColors.P3,
                values: Data.Labels.map(function(label, i) {
                    return { x: label, y: Data.Series.P3[i] || 0 };
                })
            },
            {
                key: 'P4 - Low',
                color: PriorityColors.P4,
                values: Data.Labels.map(function(label, i) {
                    return { x: label, y: Data.Series.P4[i] || 0 };
                })
            }
        ];

        nv.addGraph(function() {
            // Calculate max value across all series for forceY
            var maxValue = 0;
            chartData.forEach(function(series) {
                series.values.forEach(function(d) {
                    if (d.y > maxValue) maxValue = d.y;
                });
            });

            var chart = nv.models.multiBarChart()
                .margin({top: 40, right: 20, bottom: 80, left: 60})
                .x(function(d) { return d.x; })
                .y(function(d) { return d.y; })
                .stacked(true)
                .showControls(true)
                .showLegend(true)
                .color(function(d) { return d.color; })
                .forceY([0, maxValue * 1.15]);

            chart.xAxis
                .axisLabel('Time Period')
                .rotateLabels(-45);

            chart.yAxis
                .axisLabel('Incident Count')
                .tickFormat(d3.format(',.0f'));

            d3.select(Selector)
                .datum(chartData)
                .call(chart);

            nv.utils.windowResize(chart.update);

            return chart;
        });
    };

    /**
     * @name DrawSourceChart
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with Labels and Values
     * @description
     *      Draw a pie chart showing source distribution (Event Monitoring vs Manual).
     */
    TargetNS.DrawSourceChart = function(Selector, Data) {
        if (!Data || !Data.Labels || Data.Labels.length === 0) {
            $(Selector).parent().html('<p class="Center">No source data available.</p>');
            return;
        }

        // Prepare data for NVD3 pie chart
        var chartData = Data.Labels.map(function(label, i) {
            return {
                label: label,
                value: Data.Values[i] || 0,
                color: SourceColors[label] || '#999'
            };
        });

        nv.addGraph(function() {
            var chart = nv.models.pieChart()
                .x(function(d) { return d.label; })
                .y(function(d) { return d.value; })
                .showLabels(true)
                .labelType("percent")
                .donut(true)
                .donutRatio(0.35)
                .color(function(d) { return d.data.color; })
                .pieLabelsOutside(false)
                .growOnHover(false);

            chart.legend.updateState(false);
            chart.dispatch.on('chartClick', null);
            chart.dispatch.on('elementClick', null);

            d3.select(Selector)
                .datum(chartData)
                .transition().duration(350)
                .call(chart);

            // Remove pointer cursor from pie slices
            d3.select(Selector).selectAll('.nv-slice').style('cursor', 'default');

            nv.utils.windowResize(chart.update);

            return chart;
        });
    };

    /**
     * @name DrawStateChart
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with States and Counts
     * @description
     *      Draw a horizontal bar chart showing incident state distribution.
     */
    TargetNS.DrawStateChart = function(Selector, Data) {
        if (!Data || !Data.States || Data.States.length === 0) {
            $(Selector).parent().html('<p class="Center">No state data available.</p>');
            return;
        }

        // Prepare data for NVD3 horizontal bar chart
        var chartData = [{
            key: 'Incidents by State',
            values: Data.States.map(function(state, i) {
                return {
                    label: state,
                    value: Data.Counts[i] || 0
                };
            })
        }];

        nv.addGraph(function() {
            // Calculate max value for forceY to add headroom for labels
            var maxValue = d3.max(chartData[0].values, function(d) { return d.value; }) || 0;

            var chart = nv.models.multiBarHorizontalChart()
                .margin({top: 30, right: 60, bottom: 50, left: 100})
                .x(function(d) { return d.label; })
                .y(function(d) { return d.value; })
                .showValues(true)
                .showLegend(false)
                .showControls(false)
                .forceY([0, maxValue * 1.15]);

            chart.yAxis
                .axisLabel('Incident Count')
                .tickFormat(d3.format(',.0f'));

            d3.select(Selector)
                .datum(chartData)
                .call(chart);

            nv.utils.windowResize(chart.update);

            return chart;
        });
    };

    /**
     * @name DrawTopDevicesChart
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with Devices and Counts
     * @description
     *      Draw a horizontal bar chart showing top 10 devices by incident count.
     */
    TargetNS.DrawTopDevicesChart = function(Selector, Data) {
        if (!Data || !Data.Devices || Data.Devices.length === 0) {
            $(Selector).parent().html('<p class="Center">No device data available.</p>');
            return;
        }

        // Prepare data for NVD3 horizontal bar chart
        var chartData = [{
            key: 'Top Problem Devices',
            values: Data.Devices.map(function(device, i) {
                return {
                    label: device,
                    value: Data.Counts[i] || 0
                };
            })
        }];

        nv.addGraph(function() {
            // Calculate max value for forceY to add headroom for labels
            var maxValue = d3.max(chartData[0].values, function(d) { return d.value; }) || 0;

            var chart = nv.models.multiBarHorizontalChart()
                .margin({top: 30, right: 60, bottom: 50, left: 100})
                .x(function(d) { return d.label; })
                .y(function(d) { return d.value; })
                .showValues(true)
                .showLegend(false)
                .showControls(false)
                .color(['#FF5722'])
                .forceY([0, maxValue * 1.15]);

            chart.yAxis
                .axisLabel('Incident Count')
                .tickFormat(d3.format(',.0f'));

            d3.select(Selector)
                .datum(chartData)
                .call(chart);

            nv.utils.windowResize(chart.update);

            return chart;
        });
    };

    /**
     * @name DrawResolutionTimeChart
     * @memberof Core.Agent.IncidentReportCharts
     * @function
     * @param {String} Selector - SVG element selector
     * @param {Object} Data - Chart data with Buckets and Counts
     * @description
     *      Draw a histogram showing resolution time distribution.
     */
    TargetNS.DrawResolutionTimeChart = function(Selector, Data) {
        if (!Data || !Data.Buckets || Data.Buckets.length === 0) {
            $(Selector).parent().html('<p class="Center">No resolution time data available.</p>');
            return;
        }

        // Prepare data for NVD3 discrete bar chart
        var chartData = [{
            key: 'Resolution Time Distribution',
            values: Data.Buckets.map(function(bucket, i) {
                return {
                    label: bucket,
                    value: Data.Counts[i] || 0
                };
            })
        }];

        nv.addGraph(function() {
            // Calculate max value for forceY to add headroom for labels
            var maxValue = d3.max(chartData[0].values, function(d) { return d.value; }) || 0;

            var chart = nv.models.discreteBarChart()
                .margin({top: 40, right: 20, bottom: 50, left: 60})
                .x(function(d) { return d.label; })
                .y(function(d) { return d.value; })
                .showValues(true)
                .color(['#009688'])
                .forceY([0, maxValue * 1.15]);

            chart.xAxis
                .axisLabel('Resolution Time Range');

            chart.yAxis
                .axisLabel('Incident Count')
                .tickFormat(d3.format(',.0f'));

            d3.select(Selector)
                .datum(chartData)
                .call(chart);

            nv.utils.windowResize(chart.update);

            return chart;
        });
    };

    return TargetNS;

}(Core.Agent.IncidentReportCharts || {}));
