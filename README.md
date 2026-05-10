# Auctionator 2.5.3 Compatibility Patch Notes

This thread focused on getting **Auctionator 9.2.31-bcc** working properly on a **TBC 2.5.3 client/server**, even though the addon was originally designed around **TBC Classic 2.5.4** behavior.

## What We Fixed

- Identified that Auctionator 9.2.31-bcc was built for **TBC 2.5.4**, while the target server/client is **2.5.3**.

- Found that the addon UI could load, post auctions, and buy auctions, but AH querying was partially broken.

- Patched `Scan.lua` so Auctionator uses a **2.5.3-safe older `QueryAuctionItems` call format**.

- Removed/avoided newer AH query arguments that caused searches to stall or return no usable results on the 2.5.3 server.

- Removed the scan dependency on seller/owner names, since the server does not appear to reliably return owner data.

- Confirmed that `CanSendAuctionQuery()` was returning `true`, meaning the basic AH throttle gate was not the root issue.

## Shopping Tab Progress

- Restored Shopping tab search functionality.

- Confirmed that Auctionator can now search for items such as:
  - Netherweave Cloth
  - Mote of Shadow
  - Primal Shadow
  - Super Mana Potion

- Confirmed that search results return valid auction prices and quantities.

## Full Scan Fix

- Found that Auctionator’s original full scan stalled at **10%** because the server did not respond properly to the GetAll-style full scan query.

- Replaced the broken GetAll-style scan behavior with a **slower page-by-page full scan fallback**.

- Confirmed that the new full scan successfully processed auction data.

## Selling Tab Fixes

- Found that the Selling tab did not automatically show competing auctions or update prices correctly at first.

- Patched the Selling tab flow so selecting an item now forces a current-auction search.

- Confirmed that selecting an item in the Selling tab now updates the sell price correctly based on current AH prices.

- Added debug commands to help verify Selling tab behavior:
  - `/a253state`
  - `/a253sell`
  - `/a253sellbox`

- Verified through debug output that Auctionator was finding and building auction rows even when the UI did not display them.

## Remaining UI Problem Found

- Determined that the final issue was not scanning or data collection.

- The Selling tab had valid auction rows internally, but the embedded Auctionator results table was not visually rendering correctly.

- Evidence of a UI/layout issue included:
  - Blank lower Selling results box
  - Double scrollbars
  - Overlapping buttons
  - Results existing in debug output but not showing in the frame

## Custom Selling Rows Overlay

- Built a custom visual overlay for the Selling tab to display competing auctions directly in the blank lower box.

- The overlay shows:
  - Unit price
  - Available quantity
  - Stack price
  - Seller name, when available

- Since the server does not reliably return seller/owner names, seller values may show as `?`.

- Iterated the overlay through multiple versions to:
  - Fit inside the Selling tab box
  - Avoid the broken built-in double-scrollbar area
  - Hide when the History view is opened
  - Keep the current-auction display compact and readable

## Current Working Setup

The current working setup uses:

- Patched `Scan.lua`
- Patched `Throttling.lua`
