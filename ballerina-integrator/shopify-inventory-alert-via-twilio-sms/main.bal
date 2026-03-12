import ballerina/io;
import ballerina/lang.runtime;

// Track products with cooldown period to avoid duplicate alerts
map<AlertCooldown> cooldownTracker = {};

public function main() returns error? {
    int recipientCount = twilioRecipientNumbers.length();
    io:println("Starting Shopify Inventory Monitor | threshold=" + inventoryThreshold.toString() +
        " pollingInterval=" + pollingIntervalSeconds.toString() +
        " cooldownPeriod=" + cooldownPeriodHours.toString() +
        " recipients=" + recipientCount.toString());

    int productIdCount = productIdsToMonitor.length();
    if productIdCount > 0 {
        io:println("Monitoring specific product IDs: " + productIdsToMonitor.toString());
    } else {
        io:println("Monitoring all products");
    }

    while true {
        error? result = checkAndNotifyInventory();
        if result is error {
            var errorDetail = result.detail();
            if errorDetail["statusCode"] == 401 {
                io:println("ERROR: Shopify authentication failed: invalid API key or access token. " +
                    "Verify your shopifyAccessToken configuration and redeploy.");
                return;
            }
            string errorMessage = result.message();
            io:println("ERROR: Error checking inventory: " + errorMessage);
        }

        // Wait for the next polling interval
        runtime:sleep(pollingIntervalSeconds);
    }
}

