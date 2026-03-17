import ballerina/crypto;
import ballerina/http;
import ballerina/log;

// Track per-SKU and per-recipient cooldowns to avoid duplicate alerts within the cooldown window.
// NOTE: This map is process-local (in-memory only). State is lost on restart.
map<AlertCooldown> cooldownTracker = {};

function init() {
    log:printInfo("Shopify inventory alert service started. Listening for Shopify order events",
        port = 8090,
        inventoryThreshold = inventoryThreshold,
        cooldownPeriodHours = cooldownPeriodHours);
}

service / on httpListener {

    resource function post .(http:Caller caller, http:Request request) returns error? {
        byte[] rawPayload = check request.getBinaryPayload();

        // Validate Shopify HMAC-SHA256 signature
        string|http:HeaderNotFoundError hmacResult = request.getHeader("X-Shopify-Hmac-Sha256");
        if hmacResult is http:HeaderNotFoundError {
            log:printWarn("Rejected webhook: missing X-Shopify-Hmac-Sha256 header");
            http:Response res = new;
            res.statusCode = http:STATUS_UNAUTHORIZED;
            check caller->respond(res);
            return;
        }
        byte[] computedHmac = check crypto:hmacSha256(rawPayload, shopifyConfig.apiSecretKey.toBytes());
        if computedHmac.toBase64() != hmacResult {
            log:printWarn("Rejected webhook: HMAC signature mismatch");
            http:Response res = new;
            res.statusCode = http:STATUS_UNAUTHORIZED;
            check caller->respond(res);
            return;
        }

        // Parse JSON payload
        string rawStr = check string:fromBytes(rawPayload);
        json payload = check rawStr.fromJsonString();

        // Determine webhook topic
        string|http:HeaderNotFoundError topicResult = request.getHeader("X-Shopify-Topic");
        string topic = topicResult is string ? topicResult : "unknown";

        // Log incoming webhook in a structured, readable way
        logWebhookPayload(topic, payload, rawStr);

        if topic == "orders/create" {
            check handleOrdersCreate(payload);
        }

        http:Response response = new;
        check caller->respond(response);
    }
}

// Logs the incoming webhook with key metadata as structured fields and the full raw payload.
function logWebhookPayload(string topic, json payload, string rawStr) {
    if !(payload is map<json>) {
        log:printInfo("Shopify webhook received", topic = topic, rawPayload = rawStr);
        return;
    }

    json idJson = payload["id"];
    int orderId = idJson is int ? idJson : 0;

    json lineItemsJson = payload["line_items"];
    int lineItemCount = lineItemsJson is json[] ? lineItemsJson.length() : 0;

    string customerEmail = "";
    json customerJson = payload["customer"];
    if customerJson is map<json> {
        json emailJson = customerJson["email"];
        customerEmail = emailJson is string ? emailJson : "";
    }

    log:printInfo("Shopify webhook received",
        topic = topic,
        orderId = orderId,
        lineItemCount = lineItemCount,
        customerEmail = customerEmail,
        rawPayload = rawStr);
}

// Handle orders/create webhook: extract line items and trigger inventory checks.
function handleOrdersCreate(json payload) returns error? {
    if !(payload is map<json>) {
        log:printWarn("Unexpected webhook payload: not a JSON object");
        return;
    }

    json idJson = payload["id"];
    int orderId = idJson is int ? idJson : 0;
    log:printInfo("Trigger fired: new Shopify order received", orderId = orderId);

    json lineItemsJson = payload["line_items"];
    if !(lineItemsJson is json[]) || lineItemsJson.length() == 0 {
        log:printInfo("No line items found in order", orderId = orderId);
        return;
    }

    LineItemInfo[] lineItems = [];
    foreach json item in lineItemsJson {
        if item is map<json> {
            json pid = item["product_id"];
            json vid = item["variant_id"];
            lineItems.push({
                product_id: pid is int ? pid : 0,
                variant_id: vid is int ? vid : 0
            });
        }
    }

    check processOrderedLineItems(lineItems);
}
