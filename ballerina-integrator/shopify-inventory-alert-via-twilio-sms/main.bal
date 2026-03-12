import ballerina/io;
import ballerina/lang.runtime;

// Track products with cooldown period to avoid duplicate alerts
map<AlertCooldown> cooldownTracker = {};

public function main() returns error? {
    io:println("Starting Shopify Inventory Monitor | threshold=" + inventoryThreshold.toString() +
        " pollingInterval=" + pollingIntervalSeconds.toString() +
        " cooldownPeriod=" + cooldownPeriodHours.toString() +
        " recipients=" + twilioRecipientNumbers.length().toString());

    if productIdsToMonitor.length() > 0 {
        io:println("Monitoring specific product IDs: " + productIdsToMonitor.toString());
    } else {
        io:println("Monitoring all products");
    }

    while true {
        error? result = checkAndNotifyInventory();
        if result is error {
            var detail = result.detail();
            if detail is map<anydata> && detail["statusCode"] == 401 {
                io:println("ERROR: Shopify authentication failed: invalid API key or access token. " +
                    "Verify your shopifyAccessToken configuration and redeploy.");
                return;
            }
            io:println("ERROR: Error checking inventory: " + result.message());
        }

        // Wait for the next polling interval
        runtime:sleep(pollingIntervalSeconds);
    }
}

