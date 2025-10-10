#!/usr/bin/env node

const QueueManager = require('./queue-manager');
const express = require('express');
const path = require('path');
require('dotenv').config();

class QueueMonitor {
    constructor() {
        this.app = express();
        this.queueManager = new QueueManager();
        this.port = process.env.MONITOR_PORT || 3004;
        
        this.setupRoutes();
        this.setupWebSocket();
    }

    setupRoutes() {
        this.app.use(express.json());
        this.app.use(express.static(path.join(__dirname, 'public')));

        // API Routes
        this.app.get('/api/stats', async (req, res) => {
            try {
                const stats = await this.queueManager.getAllStats();
                res.json({ success: true, data: stats });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.get('/api/tenant/:tenantId/stats', async (req, res) => {
            try {
                const stats = await this.queueManager.getQueueStats(req.params.tenantId);
                res.json({ success: true, data: stats });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.post('/api/tenant/:tenantId/pause', async (req, res) => {
            try {
                await this.queueManager.pauseQueue(req.params.tenantId);
                res.json({ success: true, message: 'Queue paused' });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.post('/api/tenant/:tenantId/resume', async (req, res) => {
            try {
                await this.queueManager.resumeQueue(req.params.tenantId);
                res.json({ success: true, message: 'Queue resumed' });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.post('/api/tenant/:tenantId/clear', async (req, res) => {
            try {
                await this.queueManager.clearQueue(req.params.tenantId);
                res.json({ success: true, message: 'Queue cleared' });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        // Bulk operations
        this.app.post('/api/bulk/pdf', async (req, res) => {
            try {
                const { tenantId, invoices, options = {} } = req.body;
                
                if (!tenantId || !invoices || !Array.isArray(invoices)) {
                    return res.status(400).json({ 
                        success: false, 
                        error: 'tenantId and invoices array required' 
                    });
                }

                const jobIds = [];
                for (const invoice of invoices) {
                    const job = await this.queueManager.addPdfJob(tenantId, invoice, options);
                    jobIds.push(job.id);
                }

                res.json({ 
                    success: true, 
                    message: `Added ${jobIds.length} PDF jobs to queue`,
                    jobIds 
                });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.post('/api/bulk/email', async (req, res) => {
            try {
                const { tenantId, emailJobs } = req.body;
                
                if (!tenantId || !emailJobs || !Array.isArray(emailJobs)) {
                    return res.status(400).json({ 
                        success: false, 
                        error: 'tenantId and emailJobs array required' 
                    });
                }

                const jobIds = [];
                for (const emailJob of emailJobs) {
                    const job = await this.queueManager.addEmailJob(
                        tenantId, 
                        emailJob.invoiceData, 
                        emailJob.emailData, 
                        emailJob.pdfPath
                    );
                    jobIds.push(job.id);
                }

                res.json({ 
                    success: true, 
                    message: `Added ${jobIds.length} email jobs to queue`,
                    jobIds 
                });
            } catch (error) {
                res.status(500).json({ success: false, error: error.message });
            }
        });
    }

    setupWebSocket() {
        // WebSocket for real-time updates
        const WebSocket = require('ws');
        this.wss = new WebSocket.Server({ port: 3005 });
        
        this.wss.on('connection', (ws) => {
            console.log('📡 WebSocket client connected');
            
            // Send initial stats
            this.sendStats(ws);
            
            // Send stats every 5 seconds
            const interval = setInterval(() => {
                this.sendStats(ws);
            }, 5000);
            
            ws.on('close', () => {
                clearInterval(interval);
                console.log('📡 WebSocket client disconnected');
            });
        });
    }

    async sendStats(ws) {
        try {
            const stats = await this.queueManager.getAllStats();
            ws.send(JSON.stringify({ type: 'stats', data: stats }));
        } catch (error) {
            ws.send(JSON.stringify({ type: 'error', error: error.message }));
        }
    }

    start() {
        this.app.listen(this.port, () => {
            console.log(`📊 Queue Monitor running on port ${this.port}`);
            console.log(`🌐 Dashboard: http://localhost:${this.port}`);
            console.log(`📡 WebSocket: ws://localhost:3005`);
        });
    }
}

// Start monitor if this file is run directly
if (require.main === module) {
    const monitor = new QueueMonitor();
    monitor.start();
}

module.exports = QueueMonitor;
