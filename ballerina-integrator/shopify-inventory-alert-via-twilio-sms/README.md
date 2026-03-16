# Shopify Inventory Alert via Twilio SMS

## Description

This integration listens for new orders on your Shopify store and automatically sends SMS notifications via Twilio when an ordered product's inventory falls below a defined threshold.

### What It Does

- Receives a real-time webhook from Shopify whenever a new order is created
- Checks the current inventory level of each product variant in the order against a configurable threshold
- Sends SMS alerts to one or more recipient phone numbers when stock is low
- Enforces a per-SKU cooldown period to prevent duplicate alerts within a configured time window
- Supports a fully customizable SMS message template with product-specific placeholders

## Prerequisites

Before running this integration, you need:

### Shopify Setup

1. A Shopify store with Admin API access
2. A Shopify Admin API access token with the following scope: `read_products`
3. Your store's permanent `.myshopify.com` domain
4. A webhook configured to send order creation events to this integration (see **Shopify Webhook Setup** below)

Follow the step-by-step guide below to obtain the access token manually.

### Twilio Setup

1. A Twilio account with an active SMS-capable phone number
2. The recipient country must be enabled under **Twilio Console → Messaging → Settings → Geo Permissions**
3. For trial accounts, recipient numbers must be verified under **Twilio Console → Phone Numbers → Verified Caller IDs**

---

## How to Obtain the Shopify Access Token Manually

> **Note:** As of January 2026, Shopify no longer supports creating new legacy custom apps directly from the store admin. You must now create apps through the **Shopify Dev Dashboard** and use the **client credentials flow** to obtain an access token.

### Step 1 — Find Your Store URL

Your store URL is in the format:
```
https://<your-store-name>.myshopify.com
```
You can find it in the browser address bar when logged into your Shopify admin.

> Always use the `.myshopify.com` domain, not any custom domain.

---

### Step 2 — Create a Custom App in the Dev Dashboard

1. Log in to [Shopify Admin](https://admin.shopify.com).
2. Go to **Settings → Apps and sales channels**.
3. Click **Develop apps**, then click **Build apps** — this opens the Dev Dashboard.
4. Click **Create app**.
5. Enter an app name (e.g., `Inventory Alert Bot`) and click **Create app**.

---

### Step 3 — Configure API Scopes

1. Inside your new app, click the **Configuration** tab.
2. Under **Admin API integration**, click **Configure**.
3. Enable the following scopes:
   - `read_products` — required to read product and inventory data
4. Click **Save**.

---

### Step 4 — Install the App on Your Store

1. In the Dev Dashboard, open your app.
2. Click **Install app** and confirm the installation.

The app must be installed before any access token can be issued.

---

### Step 5 — Copy Your Client ID and Client Secret

1. In your app, go to the **Settings** tab (or **API credentials** section).
2. Copy the **Client ID** and **Client Secret** — you will need both to request an access token.

> Keep the client secret private. Never commit it to source control.

---

### Step 6 — Request an Access Token via cURL

Run the following command in your terminal, replacing the placeholders:

```bash
curl -X POST "https://<your-store-name>.myshopify.com/admin/oauth/access_token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=<your-client-id>&client_secret=<your-client-secret>"
```

**Example response:**
```json
{
  "access_token": "shpat_xxxxxxxxxxxxxxxxxxxxxxxxxx",
  "scope": "read_products",
  "expires_in": 86399
}
```

Copy the `access_token` value — this is your `shopifyConfig.accessToken`.

> **Token expiry:** The token is valid for approximately **24 hours**. When it expires, repeat this cURL command to generate a new one and update your configuration.

---

### Step 7 — Map Credentials to Config

```toml
# Config.toml

[shopifyConfig]
storeUrl     = "https://your-store-name.myshopify.com"
accessToken  = "shpat_xxxxxxxxxxxxxxxxxxxxxxxxxx"
apiSecretKey = "<webhook-signing-secret>"   # obtained in Shopify Webhook Setup below
```

---

### Troubleshooting

| Error | Likely Cause | Fix |
|---|---|---|
| `{"error":"invalid_client"}` | Wrong client ID or secret | Re-copy credentials from the Dev Dashboard |
| `{"error":"invalid_grant"}` | App not installed on store | Install the app (Step 4) |
| `401 Unauthorized` on API call | Token expired or wrong | Re-run the cURL command (Step 6) to get a fresh token |
| `403 Forbidden` on API call | Missing API scope | Add `read_products` under app Configuration (Step 3) |
| `404 Not Found` | Wrong store URL | Use the `.myshopify.com` URL, not a custom domain |

---

## Configuration

The following configurations are required to connect to Shopify and Twilio.

### Shopify Credentials

- `storeUrl` - Your store URL (e.g., `https://your-store.myshopify.com`)
- `accessToken` - Admin API access token (`shpat_...`)
- `apiSecretKey` - Webhook signing secret used to verify incoming webhook requests from Shopify

### Twilio Credentials

- `accountSid` - Your Twilio Account SID (`AC...`)
- `authToken` - Your Twilio Auth Token
- `fromNumber` - Your Twilio phone number in E.164 format (e.g., `+12025551234`)
- `recipientNumbers` - One or more recipient phone numbers in E.164 format

### Inventory Monitoring

- `inventoryThreshold` - Minimum stock level that triggers an alert (default: `10`)
- `cooldownPeriodHours` - Minimum hours before re-alerting on the same SKU (default: `24`)

### Notification Settings

- `smsTemplate` - Customizable SMS message using the placeholders below

#### SMS Template Placeholders

- `{{product.id}}` - Shopify product ID
- `{{product.name}}` - Display name of the product
- `{{product.inventory}}` - Current stock quantity
- `{{product.sku}}` - Product variant SKU
- `{{threshold}}` - Configured inventory threshold

**Default template:**
```text
INVENTORY ALERT: {{product.name}} (ID: {{product.id}}) is low on stock. Current inventory: {{product.inventory}}. SKU: {{product.sku}}. Threshold: {{threshold}}
```

**Example output:**
```text
INVENTORY ALERT: Blue Denim Jacket (ID: 8194105999407) is low on stock. Current inventory: 3. SKU: BDJ-001. Threshold: 10
```

## Shopify Webhook Setup

After deploying the integration, register a webhook in Shopify to forward order creation events:

1. In Shopify Admin, go to **Settings → Notifications → Webhooks**
2. Click **Create webhook**
3. Set **Event** to `Order creation`
4. Set **URL** to `https://<your-deployed-host>/shopify`
5. Set **Format** to `JSON`
6. Copy the **Signing secret** shown on the webhook — use this as `shopifyConfig.apiSecretKey`

## Deploying on **Devant**

1. Sign in to your Devant account.
2. Create a new Integration and follow the instructions in [Devant Documentation](https://wso2.com/devant/docs/references/import-a-repository/) to import this repository.
3. Select the **Technology** as `WSO2 Integrator: BI`.
4. Choose the **Integration Type** as `Trigger` and click **Create**.
5. Once the build is successful, click **Configure to Continue** and set up the required environment variables for Shopify and Twilio credentials.
6. Click **Deploy** to start the integration.
7. Copy the public URL of the deployed integration and register it as a Shopify webhook (see **Shopify Webhook Setup** above).
8. Once tested, promote the integration to production. Make sure to set the relevant environment variables in the production environment as well.
