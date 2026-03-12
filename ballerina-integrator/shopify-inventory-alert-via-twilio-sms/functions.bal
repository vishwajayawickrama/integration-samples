import ballerina/io;
import ballerina/time;
import ballerinax/shopify.admin;
import ballerinax/twilio;

// Function to fetch products from Shopify
function getShopifyProducts() returns Product[]|error {
    admin:ProductList response = check adminClient->getProducts();
    anydata productsData = response["products"];
    if productsData is () {
        return [];
    }
    admin:Product[] adminProducts = check productsData.cloneWithType();

    Product[] products = [];
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
                string productKey = skuValue != "" ? skuValue : string `${productTitle} - ${variantTitle}`;

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

// Function to send SMS via Twilio to multiple recipients
function sendInventoryAlert(ProductInventoryInfo productInfo) returns error? {
    string messageBody = formatSmsMessage(productInfo);

    foreach string recipientNumber in twilioRecipientNumbers {
        twilio:CreateMessageRequest messageRequest = {
            To: recipientNumber,
            From: twilioFromNumber,
            Body: messageBody
        };

        twilio:Message _ = check twilioClient->createMessage(messageRequest);
    }
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

        // Send SMS alert to all recipients
        string productName = productInfo.productName;
        int currentInventory = productInfo.inventory;
        io:println("Sending inventory alert | product=\"" + productName +
            "\" sku=" + sku + " inventory=" + currentInventory.toString());
        error? sendResult = sendInventoryAlert(productInfo);

        if sendResult is error {
            string errorMessage = sendResult.message();
            io:println("ERROR: Failed to send alert for \"" + productName + "\": " + errorMessage);
        } else {
            int recipientCount = twilioRecipientNumbers.length();
            io:println("Alert sent successfully to " + recipientCount.toString() + " recipient(s)");

            // Update cooldown tracker
            decimal currentTime = time:monotonicNow();
            cooldownTracker[sku] = {
                lastAlertTime: currentTime,
                inventory: currentInventory
            };
        }
    }
}
