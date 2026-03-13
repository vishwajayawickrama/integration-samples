import ballerina/io;
import ballerina/time;
import ballerinax/shopify.admin;
import ballerinax/twilio;

// Function to fetch products from Shopify
// Paginates using limit=250 and sinceId until a page returns fewer than 250 products.
function getShopifyProducts() returns Product[]|error {
    Product[] products = [];
    int pageLimit = 250;
    string? sinceId = ();

    while true {
        admin:ProductList response = check adminClient->getProducts('limit = pageLimit, sinceId = sinceId);
        anydata productsData = response["products"];
        if productsData is () {
            break;
        }
        admin:Product[] adminProducts = check productsData.cloneWithType();
        if adminProducts.length() == 0 {
            break;
        }

        foreach admin:Product adminProduct in adminProducts {
            int productId = adminProduct?.id ?: 0;
            string productTitle = adminProduct?.title ?: "";
            string? productVendor = adminProduct?.vendor;

            ProductVariant[] variants = [];
            admin:ProductVariant[]? adminVariants = adminProduct?.variants;
            if adminVariants is admin:ProductVariant[] {
                foreach admin:ProductVariant adminVariant in adminVariants {
                    int variantId = adminVariant?.id ?: 0;
                    string variantTitle = adminVariant?.title ?: "";
                    int? inventoryQty = adminVariant?.inventory_quantity;
                    string? variantSku = adminVariant?.sku;

                    variants.push({
                        id: variantId,
                        title: variantTitle,
                        inventory_quantity: inventoryQty,
                        sku: variantSku
                    });
                }
            }

            products.push({id: productId, title: productTitle, vendor: productVendor, variants: variants});
        }

        if adminProducts.length() < pageLimit {
            break;
        }

        // Use the last product's id as sinceId for the next page
        int lastId = adminProducts[adminProducts.length() - 1]?.id ?: 0;
        sinceId = lastId.toString();
    }

    return products;
}

// Function to filter products based on configured product IDs
function filterProducts(Product[] products) returns Product[] {
    if productIdsToMonitor.length() == 0 {
        return products;
    }

    Product[] filteredProducts = [];
    foreach Product product in products {
        if productIdsToMonitor.indexOf(product.id) is int {
            filteredProducts.push(product);
        }
    }

    return filteredProducts;
}

// Function to check if inventory is below threshold
function checkInventoryLevels(Product[] products) returns map<ProductInventoryInfo> {
    map<ProductInventoryInfo> lowInventoryProducts = {};

    foreach Product product in products {
        foreach ProductVariant variant in product.variants {
            int? inventoryQuantity = variant?.inventory_quantity;
            if inventoryQuantity is int && inventoryQuantity < inventoryThreshold {
                string? variantSku = variant?.sku;
                string skuValue = variantSku is string ? variantSku : "";
                string productTitle = product.title;
                string variantTitle = variant.title;
                string productKey = variant.id.toString();

                lowInventoryProducts[productKey] = {
                    productId: product.id,
                    productName: productTitle,
                    variantTitle: variantTitle,
                    sku: skuValue,
                    inventory: inventoryQuantity
                };
            }
        }
    }

    return lowInventoryProducts;
}

// Function to check if cooldown period has passed
function isCooldownExpired(string sku, map<AlertCooldown> cooldownTracker) returns boolean {
    AlertCooldown? cooldownInfo = cooldownTracker[sku];

    if cooldownInfo is () {
        return true;
    }

    decimal currentTime = time:monotonicNow();
    decimal timeDifference = currentTime - cooldownInfo.lastAlertTime;
    decimal cooldownSeconds = cooldownPeriodHours * 3600.0;

    return timeDifference >= cooldownSeconds;
}

// Function to format SMS message using template
function formatSmsMessage(ProductInventoryInfo productInfo) returns string {
    string:RegExp productIdPattern = re `\{\{product\.id\}\}`;
    string:RegExp productNamePattern = re `\{\{product\.name\}\}`;
    string:RegExp inventoryPattern = re `\{\{product\.inventory\}\}`;
    string:RegExp skuPattern = re `\{\{product\.sku\}\}`;
    string:RegExp thresholdPattern = re `\{\{threshold\}\}`;

    string message = smsTemplate;
    message = productIdPattern.replaceAll(message, productInfo.productId.toString());
    message = productNamePattern.replaceAll(message, productInfo.productName);
    message = inventoryPattern.replaceAll(message, productInfo.inventory.toString());
    message = skuPattern.replaceAll(message, productInfo.sku);
    message = thresholdPattern.replaceAll(message, inventoryThreshold.toString());

    return message;
}

// Function to send SMS via Twilio to multiple recipients.
// Iterates all twilioRecipientNumbers without fail-fast: each createMessage call is made
// independently so a failure for one recipient does not abort delivery to the rest.
// Returns a per-recipient result array so the caller can track cooldown/delivery state
// per recipient and retry only failed ones.
function sendInventoryAlert(ProductInventoryInfo productInfo) returns RecipientDeliveryResult[] {
    string messageBody = formatSmsMessage(productInfo);
    RecipientDeliveryResult[] results = [];

    foreach string recipientNumber in twilioConfig.recipientNumbers {
        twilio:CreateMessageRequest messageRequest = {
            To: recipientNumber,
            From: twilioConfig.fromNumber,
            Body: messageBody
        };

        twilio:Message|error sendResult = twilioClient->createMessage(messageRequest);
        if sendResult is error {
            results.push({recipient: recipientNumber, success: false, errorDetail: sendResult.message()});
        } else {
            results.push({recipient: recipientNumber, success: true, errorDetail: ()});
        }
    }

    return results;
}

function checkAndNotifyInventory() returns error? {
    // Fetch products from Shopify
    Product[] allProducts = check getShopifyProducts();

    // Filter products based on configuration
    Product[] productsToCheck = filterProducts(allProducts);

    // Check inventory levels
    map<ProductInventoryInfo> lowInventoryProducts = checkInventoryLevels(productsToCheck);

    int lowInventoryCount = lowInventoryProducts.length();
    if lowInventoryCount == 0 {
        return;
    }

    io:println("WARN: Products with low inventory detected: " + lowInventoryCount.toString());

    // Send alerts for products that have passed cooldown period
    string[] skuKeys = lowInventoryProducts.keys();
    foreach string sku in skuKeys {
        ProductInventoryInfo productInfo = lowInventoryProducts.get(sku);

        // Check if cooldown period has expired
        if !isCooldownExpired(sku, cooldownTracker) {
            continue;
        }

        // Send SMS alert to all recipients; collect per-recipient delivery results
        string productName = productInfo.productName;
        int currentInventory = productInfo.inventory;
        io:println("Sending inventory alert | product=\"" + productName +
            "\" sku=" + sku + " inventory=" + currentInventory.toString());
        RecipientDeliveryResult[] deliveryResults = sendInventoryAlert(productInfo);

        int successCount = 0;
        foreach RecipientDeliveryResult result in deliveryResults {
            if result.success {
                successCount += 1;
            } else {
                string detail = result.errorDetail ?: "unknown error";
                io:println("ERROR: Failed to send alert to " + result.recipient +
                    " for \"" + productName + "\": " + detail);
            }
        }

        if successCount > 0 {
            io:println("Alert sent successfully to " + successCount.toString() + " of " +
                deliveryResults.length().toString() + " recipient(s)");

            // Update cooldown tracker once at least one recipient received the alert
            decimal currentTime = time:monotonicNow();
            cooldownTracker[sku] = {
                lastAlertTime: currentTime,
                inventory: currentInventory
            };
        }
    }
}
