    S([Order Created in Shopify]):::startNode
    S --> WEBHOOK[Webhook Received by onOrdersCreate]:::processNode
    WEBHOOK --> EXTRACT[Extract Line Items from Order]:::processNode
    EXTRACT --> FETCH[Fetch Current Inventory from Shopify Admin API]:::processNode
    FETCH --> CHECK{Inventory Below Threshold?}:::decisionNode
    CHECK -- No --> SKIP[Skip - Stock is Sufficient]:::processNode
    CHECK -- Yes --> COOLDOWN{Cooldown Expired?}:::decisionNode
    COOLDOWN -- No --> SKIP
    COOLDOWN -- Yes --> SEND[Send SMS Alert via Twilio]:::processNode
    SEND --> E([End]):::endNode
    SKIP --> E
