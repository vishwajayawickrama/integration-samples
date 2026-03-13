import ballerina/io;
import ballerina/lang.runtime;

// Track products with cooldown period to avoid duplicate alerts.
// NOTE: This map is process-local (in-memory only). Cooldown state is lost on restart
// and is not shared across replicas. This service MUST run as a single replica —
// multiple replicas would also cause duplicate Shopify polling and duplicate SMS alerts,
// making shared-state solutions (Redis, DB) insufficient on their own to fix correctness.
// If persistent cooldown across restarts is required, replace this map with an external
// KV store (e.g., Redis with TTL-based keys) AND ensure polling is coordinated across replicas.
map<AlertCooldown> cooldownTracker = {};

public function main() returns error? {
    int recipientCount = twilioConfig.recipientNumbers.length();
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
                return error("Shopify authentication failed: invalid API key or access token");
            }
            string errorMessage = result.message();
            io:println("ERROR: Error checking inventory: " + errorMessage);
        }

        // Wait for the next polling interval
        runtime:sleep(pollingIntervalSeconds);
    }
}

