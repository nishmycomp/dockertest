const nodemailer = require('nodemailer');
const fs = require('fs').promises;
const path = require('path');
const Handlebars = require('handlebars');
require('dotenv').config();

class EmailService {
    constructor() {
        this.transporters = new Map();
        this.initializeTransporters();
    }

    initializeTransporters() {
        // Default transporter (can be configured per tenant)
        const defaultConfig = {
            host: process.env.SMTP_HOST || 'smtp.gmail.com',
            port: parseInt(process.env.SMTP_PORT || '587'),
            secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
            auth: {
                user: process.env.SMTP_USER,
                pass: process.env.SMTP_PASS
            }
        };

        // Create default transporter
        if (defaultConfig.auth.user && defaultConfig.auth.pass) {
            this.transporters.set('default', nodemailer.createTransport(defaultConfig));
            console.log('✅ Default email transporter initialized');
        } else {
            console.warn('⚠️  SMTP credentials not configured. Email sending disabled.');
        }

        // Tenant-specific transporters can be added here
        // Example: app.imploy.com.au with custom SMTP
        const imployConfig = {
            host: process.env.IMPLOY_SMTP_HOST || defaultConfig.host,
            port: parseInt(process.env.IMPLOY_SMTP_PORT || defaultConfig.port),
            secure: process.env.IMPLOY_SMTP_SECURE === 'true',
            auth: {
                user: process.env.IMPLOY_SMTP_USER || defaultConfig.auth.user,
                pass: process.env.IMPLOY_SMTP_PASS || defaultConfig.auth.pass
            }
        };

        if (imployConfig.auth.user && imployConfig.auth.pass) {
            this.transporters.set('app_imploy_com_au', nodemailer.createTransport(imployConfig));
            console.log('✅ app.imploy.com.au email transporter initialized');
        }
    }

    getTransporter(tenantId) {
        // Try to get tenant-specific transporter, fallback to default
        return this.transporters.get(tenantId) || this.transporters.get('default');
    }

    async sendInvoiceEmail(tenantId, emailData, pdfBuffer) {
        const transporter = this.getTransporter(tenantId);
        
        if (!transporter) {
            throw new Error('Email transporter not configured');
        }

        const {
            to,
            subject,
            invoiceNumber,
            clientName,
            totalAmount,
            dueDate,
            customMessage,
            companyName,
            lineItems,
            invoiceUrl,
            isOverdue
        } = emailData;

        // Load and compile email template
        const templatePath = path.join(__dirname, 'templates', 'email-invoice.hbs');
        let htmlContent;
        
        try {
            const templateSource = await fs.readFile(templatePath, 'utf-8');
            const template = Handlebars.compile(templateSource);
            
            // Prepare line items - show first 3, then "+ X more"
            let processedLineItems = null;
            let remainingItemsCount = 0;
            
            if (lineItems && Array.isArray(lineItems) && lineItems.length > 0) {
                if (lineItems.length > 3) {
                    processedLineItems = lineItems.slice(0, 3);
                    remainingItemsCount = lineItems.length - 3;
                } else {
                    processedLineItems = lineItems;
                }
            }
            
            htmlContent = template({
                companyName: companyName || 'Imploy',
                clientName,
                invoiceNumber,
                totalAmount: parseFloat(totalAmount || 0).toFixed(2),
                dueDate,
                customMessage,
                invoiceUrl,
                isOverdue: isOverdue || false,
                lineItems: processedLineItems,
                remainingItemsCount,
                showAllItems: false, // Set to true if you want to show all items
                year: new Date().getFullYear()
            });
        } catch (error) {
            console.warn('⚠️  Template rendering failed, using fallback:', error.message);
            // Fallback to simple HTML if template not found
            htmlContent = this.getDefaultEmailTemplate(emailData);
        }

        const mailOptions = {
            from: process.env.SMTP_FROM || `"${tenantId}" <noreply@imploy.com.au>`,
            to: to,
            subject: subject || `Invoice ${invoiceNumber}`,
            html: htmlContent,
            attachments: pdfBuffer ? [{
                filename: `invoice-${invoiceNumber}.pdf`,
                content: pdfBuffer,
                contentType: 'application/pdf'
            }] : []
        };

        console.log(`📧 Sending invoice email to: ${to}`);
        
        const info = await transporter.sendMail(mailOptions);
        
        console.log('✅ Email sent successfully:', info.messageId);
        
        return {
            success: true,
            messageId: info.messageId,
            to: to,
            subject: mailOptions.subject
        };
    }

    getDefaultEmailTemplate(emailData) {
        const { clientName, invoiceNumber, totalAmount, dueDate, customMessage } = emailData;
        
        return `
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <style>
                    body { font-family: 'Inter', Arial, sans-serif; line-height: 1.6; color: #333; }
                    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
                    .header { background: linear-gradient(135deg, #412e80 0%, #bc1b8d 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
                    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 8px 8px; }
                    .invoice-details { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
                    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; }
                    .button { display: inline-block; padding: 12px 24px; background: #794d9a; color: white; text-decoration: none; border-radius: 6px; margin: 10px 0; }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>Invoice</h1>
                    </div>
                    <div class="content">
                        <p>Dear ${clientName || 'Valued Customer'},</p>
                        <p>${customMessage || 'Please find your invoice attached to this email.'}</p>
                        
                        <div class="invoice-details">
                            <h3>Invoice Details</h3>
                            <p><strong>Invoice Number:</strong> ${invoiceNumber}</p>
                            <p><strong>Amount:</strong> $${parseFloat(totalAmount || 0).toFixed(2)}</p>
                            ${dueDate ? `<p><strong>Due Date:</strong> ${dueDate}</p>` : ''}
                        </div>
                        
                        <p>If you have any questions about this invoice, please contact us.</p>
                        
                        <p>Best regards,<br>Imploy Team</p>
                    </div>
                    <div class="footer">
                        <p>&copy; ${new Date().getFullYear()} Imploy. All rights reserved.</p>
                    </div>
                </div>
            </body>
            </html>
        `;
    }

    async verifyConnection(tenantId = 'default') {
        const transporter = this.getTransporter(tenantId);
        
        if (!transporter) {
            return { success: false, message: 'Transporter not configured' };
        }

        try {
            await transporter.verify();
            return { success: true, message: 'SMTP connection verified' };
        } catch (error) {
            return { success: false, message: error.message };
        }
    }
}

module.exports = EmailService;

