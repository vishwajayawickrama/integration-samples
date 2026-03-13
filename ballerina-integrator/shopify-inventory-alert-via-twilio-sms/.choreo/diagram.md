    S([Start]):::startNode
    S --> INIT[Initialize Shopify & Twilio Clients]:::processNode
    INIT --> FETCH[Fetch & Filter Low Inventory Products]:::processNode
    FETCH --> CHECK{Low Inventory Found?}:::decisionNode
    CHECK -- No --> WAIT[Wait for Polling Interval]:::processNode
    CHECK -- Yes --> SEND[Send SMS Alert via Twilio]:::processNode
    SEND --> WAIT
    WAIT --> FETCH
    WAIT --> E([End]):::endNode
