const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const puppeteer = require('puppeteer');
const Handlebars = require('handlebars');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

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

// Main PDF generation endpoint
app.post('/generate-invoice-pdf', async (req, res) => {
    console.log('📥 Received PDF generation request');
    let browserInstance = null;
    let page = null;
    
    try {
        const { invoice } = req.body;

        if (!invoice) {
            return res.status(400).json({ error: 'Invoice data is required' });
        }

        // Load and compile template
        const templatePath = path.join(__dirname, 'templates', 'invoice-template.hbs');
        const templateSource = await fs.readFile(templatePath, 'utf-8');
        const template = Handlebars.compile(templateSource);

        // Generate HTML from template
        const html = template(invoice);

        // Get browser instance (reuse if available)
        browserInstance = await getBrowser();
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

        await page.close(); // Close page, but keep browser running

        // Send PDF as response
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="invoice-${invoice.invoice_number}.pdf"`);
        res.setHeader('Content-Length', pdfBuffer.length);
        res.send(pdfBuffer);

        console.log(`✅ PDF generated successfully for invoice ${invoice.invoice_number}`);

    } catch (error) {
        console.error('❌ Error generating PDF:', error);
        
        // Cleanup on error (close page only)
        if (page) await page.close().catch(() => {});
        
        res.status(500).json({ 
            error: 'Failed to generate PDF', 
            message: error.message 
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
