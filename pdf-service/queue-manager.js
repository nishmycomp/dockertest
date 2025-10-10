const Queue = require('bull');
const Redis = require('redis');

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
        
        this.initializeTenants();
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
                removeOnFail: 50,
                attempts: 3,
                backoff: {
                    type: 'exponential',
                    delay: 2000
                }
            }
        });

        // Rate limiting
        queue.process('generate-pdf', config.concurrency, async (job) => {
            return await this.processPdfJob(job, tenantId);
        });

        queue.process('send-email', 2, async (job) => {
            return await this.processEmailJob(job, tenantId);
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

    async startBatch(tenantId, batchId, total) {
        if (!tenantId || !batchId || !Number.isFinite(Number(total))) return;
        const key = this.getBatchKey(tenantId, batchId);
        // Initialize if not exists; always set total to latest provided
        await this.hSetCompat(key, { total: total, completed: 0, failed: 0, createdAt: Date.now() });
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
        
        console.log(`📄 Processing PDF for tenant ${config.name}: ${invoiceData.invoice_number}`);
        
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

            return {
                success: true,
                pdfPath,
                tenantId,
                invoiceNumber: invoiceData.invoice_number
            };
        } catch (error) {
            console.error(`❌ PDF generation failed for ${config.name}:`, error);
            if (batchId) {
                await this.incrBatchFailed(tenantId, batchId).catch(() => {});
            }
            throw error;
        }
    }

    async processEmailJob(job, tenantId) {
        const { invoiceData, emailData, pdfPath } = job.data;
        const config = this.tenantConfigs.get(tenantId);
        
        console.log(`📧 Sending email for tenant ${config.name}: ${invoiceData.invoice_number}`);
        
        try {
            // Email sending logic here
            await this.sendEmail(emailData, pdfPath, tenantId);
            
            return {
                success: true,
                tenantId,
                invoiceNumber: invoiceData.invoice_number,
                emailSent: true
            };
        } catch (error) {
            console.error(`❌ Email sending failed for ${config.name}:`, error);
            throw error;
        }
    }

    async generatePdf(invoiceData, tenantId) {
        // PDF generation logic using Puppeteer
        // This would use the existing PDF generation code
        // but with tenant-specific templates and configurations
        return Buffer.from('mock-pdf-data');
    }

    async storePdf(pdfBuffer, path) {
        // Store PDF to file system or cloud storage
        console.log(`💾 Storing PDF: ${path}`);
    }

    async sendEmail(emailData, pdfPath, tenantId) {
        // Email sending logic with tenant-specific SMTP settings
        console.log(`📧 Sending email to: ${emailData.to}`);
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

    async addEmailJob(tenantId, invoiceData, emailData, pdfPath) {
        const queue = this.queues.get(tenantId);
        if (!queue) {
            throw new Error(`Queue not found for tenant: ${tenantId}`);
        }

        return await queue.add('send-email', {
            invoiceData,
            emailData,
            pdfPath,
            tenantId
        });
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
}

module.exports = QueueManager;

