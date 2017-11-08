const fs = require('fs');
const exec = require('child_process').exec;
const async = require('async');
const jsonfile = require('jsonfile');
const Gauge = require("gauge");
const gauge = new Gauge();
const colors = require('colors');
const htmlToText = require('nodemailer-html-to-text').htmlToText;
const nodemailer = require('nodemailer');
const smtpPool = require('nodemailer-smtp-pool');
const LineByLineReader = require('line-by-line');
const Confirm = require('prompt-confirm');
const prompt = new Confirm('Do you want to continue process?');


let testEnv = process.argv[2] !== undefined;
let settings = null;
let queuedEmails = 0;
let failedEmails = 0;
let totalProcessedEmails = 0;
let transporter = null;
let htmlBody = null;
let totalEmails = 0;
let filename = (testEnv) ? 'include/emails.test.db' : 'include/emails.db';
let contor = 0;


const mailQueue = async.queue((payload, callback) => {
    sendMail(payload, (error) => {
        if (totalProcessedEmails == totalEmails) {
            transporter.close();
            gauge.hide();
            console.log('Sending process ended. Results: queued emails: [ ' + queuedEmails.toString().green + ' ], failed emails: [ ' + failedEmails.toString().red + ' ]');
        }
        callback(error);
    });
}, 1);

const loadMessageBody = (callback) => {
    fs.readFile('include/email.body.html', 'utf8', (error, htmlContent) => {
        htmlBody = htmlContent;
        callback(error);
    });
};

const countAddresses = (callback) => {
    exec('wc -l < ' + filename, (error, results) => {
        totalEmails = parseInt(results.replace("\n", ''));
        callback();
    });
};

const nextUrlItem = () => {
    contor++;
    contor = contor % settings.url.length;
    return settings.url[contor];
}
const loadMailerSettings = (callback) => {
    jsonfile.readFile('include/settings.json', (error, loadedObject) => {
        if (error) {
            callback(new Error('Invalid JSON File for email addresses'))
        } else {
            settings = loadedObject;
            mailQueue.concurrency = settings.queueLimit;
            callback(error, 'Mailer Settings Load');
        }
    });
};

let showInfo = (callback) => {
    process.stdout.write('\033c');
    console.log('-----------------------------------------------------------'.grey);
    console.log((testEnv) ? '>> TEST EMAIL ' + '( '.red.bold + totalEmails + ' emails )'.red.bold : '>> PRODUCTION EMAIL '.green + '( '.red.bold + totalEmails + ' emails )'.red.bold);
    console.log('-----------------------------------------------------------'.gray);
    console.log('SMTP Server:\t' + settings.smtp.hostname);
    console.log('SMTP Port:\t' + settings.smtp.port);
    console.log('SMTP SSL:\t' + settings.smtp.ssl);
    console.log('SMTP TLS:\t' + !settings.smtp.ignoreTLS);
    console.log('-----------------------------------------------------------'.gray);
    console.log('Mail From:\t' + settings.headers.from);
    console.log('Mail Address:\t' + settings.headers.address);
    console.log('Mail Subject:\t' + settings.headers.subject);
    console.log('-----------------------------------------------------------'.gray);
    console.log();

    prompt.ask((answer) => {
        callback(answer);
    });


};

const initTransporter = () => {
    var smtpObject = {
        host: settings.smtp.hostname,
        port: settings.smtp.port,
        secure: settings.smtp.ssl,
        maxConnections: settings.smtp.maxConnections,
        maxMessages: settings.smtp.maxMessages,
        ignoreTLS: settings.smtp.ignoreTLS,
        auth: null
    };
    transporter = nodemailer.createTransport(smtpPool(smtpObject));
    transporter.use('compile', htmlToText());
};

const randomId = (len) => {
    let text = "";
    let possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for (let i = 0; i < len; i++) {
        text += possible.charAt(Math.floor(Math.random() * possible.length));
    }
    return text;
};


const sendMail = (emailAddress, callback) => {
    if (typeof(emailAddress) == 'undefined' || emailAddress == null || emailAddress == '') {
        callback(new Error('Invalid Email Address'));
    } else {
        // -- replace data
        let htmlBodyClone = htmlBody;
        let subjectClone = settings.headers.subject;
        subjectClone = subjectClone.replace(/#RANDOM#/g, randomId(25));
        htmlBodyClone = htmlBodyClone.replace(/#RANDOM#/g, randomId(25));
        let urlClone = nextUrlItem();
        urlClone = urlClone.replace(/#RANDOM#/, randomId(15));
        htmlBodyClone = htmlBodyClone.replace(/#URL#/g, urlClone);
        // -- assign data
        var emailOptions = {
            from: {
                name: settings.headers.from,
                address: settings.headers.address.replace(/#RANDOM#/g, randomId(25))
            },
            to: emailAddress,
            subject: subjectClone,
            html: htmlBodyClone,
            priority: 'normal',
            xMailer: false
        };

        // -- send email
        transporter.sendMail(emailOptions, (error, info) => {
            if (error) {
                console.log(error);
                console.log(info);
                failedEmails++;
            } else {
                queuedEmails++;
            }
            totalProcessedEmails++;
            gauge.show(" ", totalProcessedEmails / totalEmails);
            gauge.pulse(emailAddress);
            callback(error);
        });
    }
};
async.parallel([loadMailerSettings, loadMessageBody, countAddresses], (errors, result) => {
    if (!errors) {
        showInfo((shouldContinue) => {
            if (shouldContinue) {
                initTransporter();
                let input = new LineByLineReader(filename);
                input.on('line', function (email) {
                    mailQueue.push(email, (error) => {
                        if (error) {
                            console.log(error);
                        }
                    });
                });
                input.on('error', function (err) {
                    console.log("Error while parsing email list file");
                });
                input.on('end', function () {
                });
            } else {
                console.log("Exiting ...");
            }
        });
    } else {
        console.log("Error while booting!");
        console.log(errors);
    }
});