const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const puppeteer = require('puppeteer');
const Handlebars = require('handlebars');
const fs = require('fs').promises;
const path = require('path');
const QueueManager = require('./queue-manager');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Initialize Queue Manager
const queueManager = new QueueManager();

// Middleware
app.use(helmet());
app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined'));

// Register Handlebars helpers
Handlebars.registerHelper('formatDate', function(date) {
    if (!date) return '';
    const d = new Date(date);
    return d.toLocaleDateString('en-AU', { year: 'numeric', month: 'short', day: 'numeric' });
});

Handlebars.registerHelper('formatCurrency', function(amount) {
    if (!amount) return '$0.00';
    return '$' + parseFloat(amount).toFixed(2).replace(/\d(?=(\d{3})+\.)/g, '$&,');
});

Handlebars.registerHelper('formatNumber', function(number) {
    if (!number && number !== 0) return '0.00';
    return parseFloat(number).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
});

Handlebars.registerHelper('add', function(a, b) {
    return parseFloat(a || 0) + parseFloat(b || 0);
});

Handlebars.registerHelper('multiply', function(a, b) {
    return parseFloat(a || 0) * parseFloat(b || 0);
});

Handlebars.registerHelper('eq', function(a, b) {
    return a === b;
});

// Browser instance pool - keep browser running for efficiency
let browser = null;
let browserPromise = null;

async function getBrowser() {
    // If browser is already running, return it
    if (browser && browser.isConnected()) {
        console.log('♻️  Reusing existing Chromium instance');
        return browser;
    }

    // If browser is starting up, wait for it
    if (browserPromise) {
        console.log('⏳ Waiting for browser to start...');
        return await browserPromise;
    }

    // Start new browser
    browserPromise = launchBrowser();
    browser = await browserPromise;
    browserPromise = null;
    
    return browser;
}

async function launchBrowser() {
    // Ultra-minimal config for Alpine Linux + Chromium
    const launchOptions = {
        headless: 'new', // Use new headless mode
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-extensions',
            '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows',
            '--disable-renderer-backgrounding'
        ],
        timeout: 120000, // 2 minutes
        dumpio: false
    };

    // Use Chromium from Alpine package
    if (process.env.PUPPETEER_EXECUTABLE_PATH) {
        launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
    }

    console.log('🚀 Launching Chromium with Alpine-optimized config...');
    console.log('   Executable:', launchOptions.executablePath || 'default');
    console.log('   Args:', launchOptions.args.join(' '));
    
    const browserInstance = await puppeteer.launch(launchOptions);
    console.log('✅ Chromium launched successfully!');
    
    // Handle browser disconnect
    browserInstance.on('disconnected', () => {
        console.log('⚠️  Browser disconnected, will restart on next request');
        browser = null;
    });
    
    return browserInstance;
}

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('🛑 SIGTERM received, shutting down gracefully...');
    if (browser) {
        console.log('🔒 Closing browser...');
        await browser.close();
    }
    process.exit(0);
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Queue stats endpoint
app.get('/queue/stats', async (req, res) => {
    try {
        const stats = await queueManager.getAllStats();
        res.json({ success: true, data: stats });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Batch lifecycle endpoints
app.post('/queue/batch/start', async (req, res) => {
    try {
        const { tenantId = 'app_imploy_com_au', batchId, total, userId, appId, uniqueName } = req.body || {};
        if (!batchId || !Number.isFinite(Number(total))) {
            return res.status(400).json({ success: false, error: 'batchId and total are required' });
        }
        await queueManager.startBatch(tenantId, String(batchId), Number(total), userId, appId, uniqueName);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/queue/batch/:tenantId/:batchId', async (req, res) => {
    try {
        const { tenantId, batchId } = req.params;
        const status = await queueManager.getBatchStatus(tenantId, String(batchId));
        if (!status) return res.status(404).json({ success: false, error: 'Batch not found' });
        res.json({ success: true, data: status });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Main PDF generation endpoint - now uses queue system
app.post('/generate-invoice-pdf', async (req, res) => {
    console.log('📥 Received PDF generation request');
    
    try {
        const { invoice, tenantId = 'app_imploy_com_au', batchId, total } = req.body;

        if (!invoice) {
            return res.status(400).json({ error: 'Invoice data is required' });
        }

        // Add job to queue instead of processing directly
        const job = await queueManager.addPdfJob(tenantId, invoice, {
            priority: 0,
            delay: 0,
            batchId: batchId || null
        });

        console.log(`✅ PDF job added to queue: ${job.id} for tenant: ${tenantId}`);
        
        res.json({
            success: true,
            message: 'PDF generation job queued successfully',
            jobId: job.id,
            tenantId: tenantId,
            status: 'queued',
            batchId: batchId || null
        });

    } catch (error) {
        console.error('❌ Error adding job to queue:', error);
        res.status(500).json({ 
            error: 'Failed to queue PDF generation job', 
            message: error.message 
        });
    }
});

// Email sending endpoint
app.post('/send-invoice-email', async (req, res) => {
    console.log('📧 Received email sending request');
    
    try {
        const { invoice, emailData, tenantId = 'app_imploy_com_au', batchId } = req.body;

        if (!invoice || !emailData || !emailData.to) {
            return res.status(400).json({ error: 'Invoice data and email recipient are required' });
        }

        // Add email job to queue
        const job = await queueManager.addEmailJob(tenantId, invoice, emailData, {
            priority: 0,
            delay: 0,
            batchId: batchId || null
        });

        console.log(`✅ Email job added to queue: ${job.id} for tenant: ${tenantId}`);
        console.log(`🔄 Job queued - waiting for worker assignment...`);
        
        res.json({
            success: true,
            message: 'Email job queued successfully',
            jobId: job.id,
            tenantId: tenantId,
            status: 'queued',
            batchId: batchId || null
        });

    } catch (error) {
        console.error('❌ Error adding email job to queue:', error);
        res.status(500).json({ 
            error: 'Failed to queue email job', 
            message: error.message 
        });
    }
});

// Bulk email sending endpoint
app.post('/send-bulk-emails', async (req, res) => {
    console.log('📧 Received bulk email sending request');
    
    try {
        const { invoices, emailTemplate, tenantId = 'app_imploy_com_au', batchId } = req.body;

        if (!invoices || !Array.isArray(invoices)) {
            return res.status(400).json({ error: 'Invoices array is required' });
        }

        const jobIds = [];
        
        for (const invoiceWithEmail of invoices) {
            const { invoice, emailData } = invoiceWithEmail;
            
            if (!emailData || !emailData.to) {
                console.warn(`Skipping invoice ${invoice.invoice_number} - no email recipient`);
                continue;
            }

            const job = await queueManager.addEmailJob(tenantId, invoice, emailData, {
                priority: 0,
                delay: 0,
                batchId: batchId || null
            });

            jobIds.push(job.id);
        }

        console.log(`✅ ${jobIds.length} email jobs queued for tenant: ${tenantId}`);
        
        res.json({
            success: true,
            message: `Queued ${jobIds.length} email jobs`,
            jobIds: jobIds,
            tenantId: tenantId,
            batchId: batchId || null
        });

    } catch (error) {
        console.error('❌ Error adding bulk email jobs to queue:', error);
        res.status(500).json({ 
            error: 'Failed to queue bulk email jobs', 
            message: error.message 
        });
    }
});

// Verify email configuration
app.get('/email/verify/:tenantId?', async (req, res) => {
    try {
        const tenantId = req.params.tenantId || 'default';
        const result = await queueManager.verifyEmailConfig(tenantId);
        
        res.json(result);
    } catch (error) {
        res.status(500).json({ 
            success: false, 
            message: error.message 
        });
    }
});

// Get recent errors for a batch or tenant
app.get('/queue/errors/:tenantId/:batchId?', async (req, res) => {
    try {
        const { tenantId, batchId } = req.params;
        const limit = parseInt(req.query.limit) || 50;
        
        const errors = await queueManager.getRecentErrors(tenantId, batchId, limit);
        
        res.json({
            success: true,
            tenantId,
            batchId: batchId || null,
            count: errors.length,
            errors
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Get timeout statistics
app.get('/queue/timeout-stats', async (req, res) => {
    try {
        const stats = queueManager.getTimeoutStats();
        res.json({
            success: true,
            data: stats
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Batch PDF generation endpoint
app.post('/generate-batch-pdf', async (req, res) => {
    console.log('📥 Received batch PDF generation request');
    
    try {
        const { invoices } = req.body;

        if (!invoices || !Array.isArray(invoices)) {
            return res.status(400).json({ error: 'Invoices array is required' });
        }

        const results = [];

        // Get browser once for all PDFs
        const browserInstance = await getBrowser();
        
        for (const invoice of invoices) {
            let page = null;
            
            try {
                // Load and compile template
                const templatePath = path.join(__dirname, 'templates', 'invoice-template.hbs');
                const templateSource = await fs.readFile(templatePath, 'utf-8');
                const template = Handlebars.compile(templateSource);

                // Generate HTML from template
                const html = template(invoice);

                // Create new page (reuse browser)
                page = await browserInstance.newPage();
                
                await page.setContent(html, { 
                    waitUntil: 'networkidle0',
                    timeout: 30000
                });

                const pdfBuffer = await page.pdf({
                    format: 'A4',
                    printBackground: true,
                    margin: {
                        top: '20mm',
                        right: '15mm',
                        bottom: '20mm',
                        left: '15mm'
                    }
                });

                await page.close(); // Close page, keep browser

                results.push({
                    invoice_number: invoice.invoice_number,
                    success: true,
                    pdf: pdfBuffer.toString('base64')
                });

                console.log(`✅ PDF generated for invoice ${invoice.invoice_number}`);

            } catch (error) {
                console.error(`❌ Error generating PDF for invoice ${invoice.invoice_number}:`, error);
                
                // Cleanup on error (close page only)
                if (page) await page.close().catch(() => {});
                
                results.push({
                    invoice_number: invoice.invoice_number,
                    success: false,
                    error: error.message
                });
            }
        }

        res.json({ 
            success: true, 
            results: results,
            total: invoices.length,
            successful: results.filter(r => r.success).length,
            failed: results.filter(r => !r.success).length
        });

        console.log(`📊 Batch PDF generation completed: ${results.filter(r => r.success).length}/${invoices.length}`);

    } catch (error) {
        console.error('❌ Error in batch PDF generation:', error);
        res.status(500).json({ 
            error: 'Failed to generate batch PDFs', 
            message: error.message 
        });
    }
});

// Start server
app.listen(PORT, () => {
    console.log(`PDF Service running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (error) => {
    console.error('Unhandled Rejection:', error);
});
