// Shopify order webhook payload - open record tolerates any field type sent by Shopify
// (avoids ConversionErrors from fields like billing_address.latitude sent as float)
type ShopifyOrderBasic record {
    int id?;
    json[] line_items?;
};

// Line item fields needed for inventory checks
type LineItemInfo record {
    int product_id?;
    int variant_id?;
};

// Cooldown tracking record
type AlertCooldown record {
    decimal lastAlertTime;
    int inventory;
};

// Product inventory information passed through the alert chain
type ProductInventoryInfo record {
    int productId;
    string productName;
    string variantTitle;
    string sku;
    int inventory;
};

// Per-recipient SMS delivery result
type RecipientDeliveryResult record {|
    string recipient;
    boolean success;
    string? errorDetail;
|};
