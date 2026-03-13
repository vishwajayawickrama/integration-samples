import ballerinax/shopify.admin;
import ballerinax/twilio;

// Twilio client
final twilio:Client twilioClient = check new ({
    auth: {
        accountSid: twilioConfig.accountSid,
        authToken: twilioConfig.authToken
    }
});

// Shopify admin client
final admin:Client adminClient = check new ({
    xShopifyAccessToken: shopifyConfig.accessToken
}, shopifyConfig.storeUrl);
