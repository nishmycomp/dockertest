const Queue = require('bull');
const Redis = require('redis');
const EmailService = require('./email-service');
const puppeteer = require('puppeteer');
const Handlebars = require('handlebars');
const fs = require('fs').promises;
const path = require('path');

class QueueManager {
    constructor() {
        this.redis = Redis.createClient({
            host: process.env.REDIS_HOST || 'localhost',
            port: process.env.REDIS_PORT || 6379,
            password: process.env.REDIS_PASSWORD || null
        });

        // Connect for node-redis v4, ignore if v3
        if (typeof this.redis.connect === 'function') {
            this.redis.connect().catch(() => {});
        }

        this.queues = new Map();
        this.tenantConfigs = new Map();
        this.emailService = new EmailService();
        this.browser = null;
        this.jobTimeouts = new Map(); // Track job timeouts
        this.timeoutChecker = null; // Timeout checker interval
        
        this.initializeTenants();
        this.initializeBrowser();
        this.startTimeoutChecker();
    }

    initializeTenants() {
        // Configure tenants
        const tenants = [
            {
                id: 'app_imploy_com_au',
                name: 'app.imploy.com.au',
                rateLimit: 100, // requests per minute
                concurrency: 5,
                emailRateLimit: 50 // emails per minute
            },
            {
                id: 'app_3_my_companionship',
                name: 'My Companionship',
                rateLimit: 100, // requests per minute
                concurrency: 5,
                emailRateLimit: 50 // emails per minute
            },
            {
                id: 'tenant_2',
                name: 'Tenant 2',
                rateLimit: 50,
                concurrency: 3,
                emailRateLimit: 25
            }
            // Add more tenants as needed
        ];

        tenants.forEach(tenant => {
            this.tenantConfigs.set(tenant.id, tenant);
            this.createQueue(tenant.id);
        });
    }

    createQueue(tenantId) {
        const config = this.tenantConfigs.get(tenantId);
        
        const queue = new Queue(`pdf-${tenantId}`, {
            redis: {
                host: process.env.REDIS_HOST || 'localhost',
                port: process.env.REDIS_PORT || 6379,
                password: process.env.REDIS_PASSWORD || null
            },
            defaultJobOptions: {
                removeOnComplete: 100,
                removeOnFail: 100, // Keep failed jobs for debugging
                attempts: 2, // Reduced to 2 attempts (1 initial + 1 retry)
                backoff: {
                    type: 'exponential',
                    delay: 3000
                }
            }
        });

        // Rate limiting
        queue.process('generate-pdf', config.concurrency, async (job) => {
            try {
                return await this.processPdfJob(job, tenantId);
            } catch (error) {
                // Even if processPdfJob throws, log and continue
                console.error(`⚠️  Unhandled PDF job error:`, error.message);
                return { success: false, error: error.message };
            }
        });

        queue.process('send-email', 2, async (job) => {
            try {
                return await this.processEmailJob(job, tenantId);
            } catch (error) {
                // Even if processEmailJob throws, log and continue
                console.error(`⚠️  Unhandled email job error:`, error.message);
                return { success: false, error: error.message };
            }
        });

        // Error event handlers
        queue.on('failed', (job, error) => {
            console.error(`❌ Job ${job.id} failed after all retries:`, error.message);
            // Job will be kept in failed queue for review
        });

        queue.on('error', (error) => {
            console.error(`❌ Queue error for ${config.name}:`, error.message);
        });

        this.queues.set(tenantId, queue);
        console.log(`✅ Queue created for tenant: ${config.name}`);
    }

    // ---- Batch helpers (Redis HSET/HINCRBY compatibility v3/v4) ----
    async hSetCompat(key, obj) {
        if (typeof this.redis.hSet === 'function') {
            // v4 style
            for (const [field, value] of Object.entries(obj)) {
                await this.redis.hSet(key, field, String(value));
            }
        } else {
            // v3 style
            for (const [field, value] of Object.entries(obj)) {
                await new Promise((resolve, reject) => this.redis.hset(key, field, String(value), (e) => e ? reject(e) : resolve()));
            }
        }
    }

    async hIncrByCompat(key, field, by) {
        if (typeof this.redis.hIncrBy === 'function') {
            await this.redis.hIncrBy(key, field, by);
        } else {
            await new Promise((resolve, reject) => this.redis.hincrby(key, field, by, (e) => e ? reject(e) : resolve()));
        }
    }

    async hGetAllCompat(key) {
        if (typeof this.redis.hGetAll === 'function') {
            return await this.redis.hGetAll(key);
        }
        return await new Promise((resolve, reject) => this.redis.hgetall(key, (e, res) => e ? reject(e) : resolve(res)));
    }

    getBatchKey(tenantId, batchId) {
        return `batch:${tenantId}:${batchId}`;
    }

    async startBatch(tenantId, batchId, total, userId = null, appId = null, uniqueName = null) {
        if (!tenantId || !batchId || !Number.isFinite(Number(total))) return;
        const key = this.getBatchKey(tenantId, batchId);
        // Initialize if not exists; always set total to latest provided
        const batchData = { 
            total: total, 
            completed: 0, 
            failed: 0, 
            createdAt: Date.now()
        };
        if (userId) {
            batchData.userId = userId;
        }
        if (appId) {
            batchData.appId = appId;
        }
        if (uniqueName) {
            batchData.uniqueName = uniqueName;
        }
        await this.hSetCompat(key, batchData);
    }

    async incrBatchCompleted(tenantId, batchId) {
        const key = this.getBatchKey(tenantId, batchId);
        await this.hIncrByCompat(key, 'completed', 1);
    }

    async incrBatchFailed(tenantId, batchId) {
        const key = this.getBatchKey(tenantId, batchId);
        await this.hIncrByCompat(key, 'failed', 1);
    }

    async getBatchStatus(tenantId, batchId) {
        const key = this.getBatchKey(tenantId, batchId);
        const data = await this.hGetAllCompat(key);
        if (!data) return null;
        return {
            tenantId,
            batchId,
            total: Number(data.total || 0),
            completed: Number(data.completed || 0),
            failed: Number(data.failed || 0),
            pending: Math.max(0, Number(data.total || 0) - Number(data.completed || 0) - Number(data.failed || 0))
        };
    }

    async processPdfJob(job, tenantId) {
        const { invoiceData, options, batchId } = job.data;
        const config = this.tenantConfigs.get(tenantId);
        const workerId = process.env.WORKER_ID || 'unknown-worker';
        
        console.log(`📄 Processing PDF for tenant ${config.name}: ${invoiceData.invoice_number} (Worker: ${workerId})`);
        
        try {
            // PDF generation logic here
            const pdfBuffer = await this.generatePdf(invoiceData, tenantId);
            
            // Store PDF
            const pdfPath = `invoices/${tenantId}/${invoiceData.invoice_number}.pdf`;
            await this.storePdf(pdfBuffer, pdfPath);
            
            // Update batch counters
            if (batchId) {
                await this.incrBatchCompleted(tenantId, batchId).catch(() => {});
            }

            console.log(`✅ PDF generated successfully: ${invoiceData.invoice_number} (Worker: ${workerId})`);

            return {
                success: true,
                pdfPath,
                tenantId,
                invoiceNumber: invoiceData.invoice_number
            };
        } catch (error) {
            console.error(`❌ PDF generation failed for ${config.name} (Worker: ${workerId}):`, error.message);
            
            // Update batch failed counter
            if (batchId) {
                await this.incrBatchFailed(tenantId, batchId).catch(() => {});
            }
            
            // Log error but don't throw - this allows the batch to continue
            await this.logJobError(tenantId, 'pdf', invoiceData.invoice_number, error.message, batchId);
            
            // Return error result instead of throwing
            return {
                success: false,
                error: error.message,
                tenantId,
                invoiceNumber: invoiceData.invoice_number
            };
        }
    }

    async processEmailJob(job, tenantId) {
        const { invoiceData, emailData, pdfPath, batchId } = job.data;
        const config = this.tenantConfigs.get(tenantId);
        const workerId = process.env.WORKER_ID || 'unknown-worker';
        
        console.log(`📧 Sending email for tenant ${config.name}: ${invoiceData.invoice_number} to ${emailData.to} (Worker: ${workerId})`);
        
        try {
            // Validate email address
            if (!emailData || !emailData.to) {
                throw new Error('No recipient email address provided');
            }
            
            // Generate PDF buffer for email attachment
            let pdfBuffer = null;
            
            if (invoiceData) {
                pdfBuffer = await this.generatePdf(invoiceData, tenantId);
            }
            
            // Send email with PDF attachment
            const result = await this.emailService.sendInvoiceEmail(
                tenantId,
                emailData,
                pdfBuffer
            );
            
            // Update batch counters if provided
            if (batchId) {
                await this.incrBatchCompleted(tenantId, batchId).catch(() => {});
            }
            
            console.log(`✅ Email sent successfully: ${invoiceData.invoice_number} to ${emailData.to} (Worker: ${workerId})`);
            
            return {
                success: true,
                tenantId,
                invoiceNumber: invoiceData.invoice_number,
                emailSent: true,
                messageId: result.messageId,
                recipient: emailData.to
            };
        } catch (error) {
            console.error(`❌ Email sending failed for ${config.name} (Worker: ${workerId}):`, error.message);
            
            // Update batch failed counter
            if (batchId) {
                await this.incrBatchFailed(tenantId, batchId).catch(() => {});
            }
            
            // Log error but don't throw - this allows the batch to continue
            await this.logJobError(tenantId, 'email', invoiceData.invoice_number, error.message, batchId, emailData.to);
            
            // Return error result instead of throwing
            return {
                success: false,
                error: error.message,
                tenantId,
                invoiceNumber: invoiceData.invoice_number,
                emailSent: false,
                recipient: emailData.to || 'unknown'
            };
        }
    }

    async initializeBrowser() {
        try {
            const launchOptions = {
                headless: 'new',
                args: [
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-dev-shm-usage',
                    '--disable-gpu',
                    '--disable-extensions'
                ],
                timeout: 120000
            };

            if (process.env.PUPPETEER_EXECUTABLE_PATH) {
                launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
            }

            this.browser = await puppeteer.launch(launchOptions);
            console.log('✅ Browser initialized for PDF generation');
            
            this.browser.on('disconnected', () => {
                console.log('⚠️  Browser disconnected, will restart on next request');
                this.browser = null;
            });
        } catch (error) {
            console.error('❌ Failed to initialize browser:', error);
        }
    }

    async getBrowser() {
        if (this.browser && this.browser.isConnected()) {
            return this.browser;
        }
        await this.initializeBrowser();
        return this.browser;
    }

    async generatePdf(invoiceData, tenantId) {
        try {
            const browser = await this.getBrowser();
            const page = await browser.newPage();
            
            // Load and compile template
            const templatePath = path.join(__dirname, 'templates', 'invoice-template.hbs');
            const templateSource = await fs.readFile(templatePath, 'utf-8');
            const template = Handlebars.compile(templateSource);
            
            // Generate HTML from template
            const html = template(invoiceData);
            
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
            
            await page.close();
            
            return pdfBuffer;
        } catch (error) {
            console.error('❌ PDF generation error:', error);
            throw error;
        }
    }

    async storePdf(pdfBuffer, path) {
        // Store PDF to file system or cloud storage
        console.log(`💾 Storing PDF: ${path}`);
        // TODO: Implement actual storage logic (S3, local filesystem, etc.)
    }

    async logJobError(tenantId, jobType, invoiceNumber, errorMessage, batchId, recipient = null) {
        try {
            const errorKey = `errors:${tenantId}:${batchId || 'individual'}`;
            const errorData = JSON.stringify({
                jobType,
                invoiceNumber,
                errorMessage,
                recipient,
                timestamp: new Date().toISOString(),
                batchId
            });

            // Store error in Redis list (latest errors)
            if (typeof this.redis.lPush === 'function') {
                await this.redis.lPush(errorKey, errorData);
                await this.redis.lTrim(errorKey, 0, 99); // Keep last 100 errors
                await this.redis.expire(errorKey, 86400 * 7); // Expire after 7 days
            } else {
                // v3 style
                await new Promise((resolve) => this.redis.lpush(errorKey, errorData, resolve));
                await new Promise((resolve) => this.redis.ltrim(errorKey, 0, 99, resolve));
                await new Promise((resolve) => this.redis.expire(errorKey, 86400 * 7, resolve));
            }

            console.log(`📝 Error logged: ${jobType} for ${invoiceNumber}`);
            
            // Send notification to Laravel app inbox
            await this.sendFailureNotification(tenantId, jobType, invoiceNumber, errorMessage, batchId, recipient);
        } catch (error) {
            console.error('Failed to log error to Redis:', error.message);
        }
    }

    async sendFailureNotification(tenantId, jobType, invoiceNumber, errorMessage, batchId, recipient = null) {
        try {
            // Determine the Laravel app URL based on tenant
            const laravelUrl = this.getLaravelUrl(tenantId);
            
            // Get userId from batch if available
            let userId = null;
            let appId = null;
            let uniqueName = null;
            
            if (batchId) {
                const batchStatus = await this.getBatchStatus(tenantId, batchId);
                userId = batchStatus?.userId || null;
                appId = batchStatus?.appId || null;
                uniqueName = batchStatus?.uniqueName || null;
            }
            
            const axios = require('axios');
            const notificationPayload = {
                jobType,
                invoiceNumber,
                errorMessage,
                recipient,
                batchId,
                tenantId,
                userId,
                appId,
                uniqueName
            };

            const response = await axios.post(
                `${laravelUrl}/api/queue/notification/job-failed`,
                notificationPayload,
                {
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-API-TOKEN': process.env.LARAVEL_API_TOKEN || ''
                    },
                    timeout: 5000 // 5 second timeout
                }
            );

            console.log(`📬 Failure notification sent to Laravel: ${response.data.message} (userId: ${userId || 'N/A'})`);
        } catch (error) {
            console.error('⚠️ Failed to send notification to Laravel:', error.message);
            // Don't throw - notification failure shouldn't stop the job processing
        }
    }

    getLaravelUrl(tenantId) {
        // Map tenant IDs to Laravel app URLs
        const tenantUrls = {
            'app_imploy_com_au': process.env.LARAVEL_URL || 'http://127.0.0.1:8000',
            'app_3_my_companionship': process.env.LARAVEL_URL || 'http://127.0.0.1:8000',
            'tenant_2': 'http://tenant2.example.com'
            // Add more tenant URLs as needed
        };

        return tenantUrls[tenantId] || process.env.LARAVEL_URL || 'http://127.0.0.1:8000';
    }

    async getRecentErrors(tenantId, batchId = null, limit = 50) {
        try {
            const errorKey = `errors:${tenantId}:${batchId || 'individual'}`;
            
            let errors;
            if (typeof this.redis.lRange === 'function') {
                errors = await this.redis.lRange(errorKey, 0, limit - 1);
            } else {
                errors = await new Promise((resolve, reject) => 
                    this.redis.lrange(errorKey, 0, limit - 1, (e, res) => e ? reject(e) : resolve(res))
                );
            }

            return errors ? errors.map(e => JSON.parse(e)) : [];
        } catch (error) {
            console.error('Failed to get errors from Redis:', error.message);
            return [];
        }
    }

    // Queue management methods
    async addPdfJob(tenantId, invoiceData, options = {}) {
        const queue = this.queues.get(tenantId);
        if (!queue) {
            throw new Error(`Queue not found for tenant: ${tenantId}`);
        }

        return await queue.add('generate-pdf', {
            invoiceData,
            options,
            tenantId,
            batchId: options.batchId || null
        }, {
            priority: options.priority || 0,
            delay: options.delay || 0
        });
    }

    async addEmailJob(tenantId, invoiceData, emailData, options = {}) {
        const queue = this.queues.get(tenantId);
        if (!queue) {
            throw new Error(`Queue not found for tenant: ${tenantId}`);
        }

        return await queue.add('send-email', {
            invoiceData,
            emailData,
            tenantId,
            batchId: options.batchId || null
        }, {
            priority: options.priority || 0,
            delay: options.delay || 0
        });
    }

    async verifyEmailConfig(tenantId = 'default') {
        return await this.emailService.verifyConnection(tenantId);
    }

    async getQueueStats(tenantId) {
        const queue = this.queues.get(tenantId);
        if (!queue) {
            return null;
        }

        const waiting = await queue.getWaiting();
        const active = await queue.getActive();
        const completed = await queue.getCompleted();
        const failed = await queue.getFailed();

        return {
            tenantId,
            waiting: waiting.length,
            active: active.length,
            completed: completed.length,
            failed: failed.length,
            total: waiting.length + active.length + completed.length + failed.length
        };
    }

    async getAllStats() {
        const stats = {};
        for (const [tenantId, queue] of this.queues) {
            stats[tenantId] = await this.getQueueStats(tenantId);
        }
        return stats;
    }

    async pauseQueue(tenantId) {
        const queue = this.queues.get(tenantId);
        if (queue) {
            await queue.pause();
            console.log(`⏸️  Queue paused for tenant: ${tenantId}`);
        }
    }

    async resumeQueue(tenantId) {
        const queue = this.queues.get(tenantId);
        if (queue) {
            await queue.resume();
            console.log(`▶️  Queue resumed for tenant: ${tenantId}`);
        }
    }

    async clearQueue(tenantId) {
        const queue = this.queues.get(tenantId);
        if (queue) {
            await queue.empty();
            console.log(`🗑️  Queue cleared for tenant: ${tenantId}`);
        }
    }

    // ---- Job Timeout Checker ----
    startTimeoutChecker() {
        // Check for timed out jobs every 30 seconds
        this.timeoutChecker = setInterval(async () => {
            await this.checkJobTimeouts();
        }, 30000); // 30 seconds
        
        console.log('⏰ Job timeout checker started (30s intervals)');
    }

    async checkJobTimeouts() {
        try {
            const now = Date.now();
            const timeoutThreshold = 5 * 60 * 1000; // 5 minutes timeout
            
            for (const [tenantId, queue] of this.queues) {
                const activeJobs = await queue.getActive();
                const waitingJobs = await queue.getWaiting();
                
                // Check active jobs for timeout
                for (const job of activeJobs) {
                    const jobAge = now - job.timestamp;
                    if (jobAge > timeoutThreshold) {
                        console.log(`⏰ Job ${job.id} timed out after ${Math.round(jobAge / 1000)}s`);
                        await this.handleJobTimeout(tenantId, job);
                    }
                }
                
                // Check waiting jobs for timeout (jobs stuck in queue)
                for (const job of waitingJobs) {
                    const jobAge = now - job.timestamp;
                    if (jobAge > timeoutThreshold) {
                        console.log(`⏰ Waiting job ${job.id} timed out after ${Math.round(jobAge / 1000)}s`);
                        await this.handleJobTimeout(tenantId, job);
                    }
                }
            }
        } catch (error) {
            console.error('❌ Error in timeout checker:', error.message);
        }
    }

    async handleJobTimeout(tenantId, job) {
        try {
            const config = this.tenantConfigs.get(tenantId);
            const jobData = job.data;
            
            console.log(`🚨 Handling timeout for job ${job.id} in ${config.name}`);
            
            // Extract job information
            let jobType = 'unknown';
            let invoiceNumber = 'unknown';
            let recipient = null;
            let batchId = jobData.batchId || null;
            
            if (job.name === 'generate-pdf') {
                jobType = 'pdf';
                invoiceNumber = jobData.invoiceData?.invoice_number || 'unknown';
            } else if (job.name === 'send-email') {
                jobType = 'email';
                invoiceNumber = jobData.invoiceData?.invoice_number || 'unknown';
                recipient = jobData.emailData?.to || null;
            }
            
            // Remove the job from queue
            await job.remove();
            
            // Send failure notification
            await this.sendFailureNotification(
                tenantId,
                jobType,
                invoiceNumber,
                `Job timed out after 5 minutes - no worker processed the job`,
                batchId,
                recipient
            );
            
            // Update batch failed counter if applicable
            if (batchId) {
                await this.incrBatchFailed(tenantId, batchId).catch(() => {});
            }
            
            console.log(`📬 Timeout notification sent for job ${job.id}`);
            
        } catch (error) {
            console.error('❌ Error handling job timeout:', error.message);
        }
    }

    // Track job start time for timeout detection
    trackJobStart(tenantId, jobId, jobType, invoiceNumber, batchId = null) {
        const key = `${tenantId}:${jobId}`;
        this.jobTimeouts.set(key, {
            tenantId,
            jobId,
            jobType,
            invoiceNumber,
            batchId,
            startTime: Date.now()
        });
    }

    // Remove job from timeout tracking when completed
    untrackJob(tenantId, jobId) {
        const key = `${tenantId}:${jobId}`;
        this.jobTimeouts.delete(key);
    }

    // Get timeout statistics
    getTimeoutStats() {
        const now = Date.now();
        const stats = {
            totalTracked: this.jobTimeouts.size,
            timeouts: [],
            active: []
        };
        
        for (const [key, job] of this.jobTimeouts) {
            const age = now - job.startTime;
            const jobInfo = {
                ...job,
                ageSeconds: Math.round(age / 1000),
                isTimedOut: age > (5 * 60 * 1000) // 5 minutes
            };
            
            if (jobInfo.isTimedOut) {
                stats.timeouts.push(jobInfo);
            } else {
                stats.active.push(jobInfo);
            }
        }
        
        return stats;
    }
}

module.exports = QueueManager;

