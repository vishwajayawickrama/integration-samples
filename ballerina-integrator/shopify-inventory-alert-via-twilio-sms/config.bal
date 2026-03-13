configurable record {
    string storeUrl;
    string accessToken;
} shopifyConfig = ?;

configurable record {
    string accountSid;
    string authToken;
    string fromNumber;
    string[] recipientNumbers;
} twilioConfig = ?;

// Inventory threshold configuration
configurable int inventoryThreshold = 10;

// Polling interval in seconds
configurable decimal pollingIntervalSeconds = 300.0;

// Product IDs to monitor (empty array means monitor all products)
configurable int[] productIdsToMonitor = [];

// SMS template with placeholders: {{product.name}}, {{product.inventory}}, {{product.sku}}
configurable string smsTemplate = "INVENTORY ALERT: {{product.name}} (ID: {{product.id}}) is low on stock. Current inventory: {{product.inventory}}. SKU: {{product.sku}}. Threshold: {{threshold}}";

// Cooldown period in hours (don't re-alert same SKU within X hours)
configurable decimal cooldownPeriodHours = 24.0;
