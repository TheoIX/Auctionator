# Auctionator
Patched Scan.lua so normal Shopping searches work by changing Auctionator’s query behavior to a 2.5.3-safe older QueryAuctionItems format.
Removed the owner-name wait gate from scan processing, since your server appears to return auction data without reliable seller/owner names.
Confirmed CanSendAuctionQuery() was not the problem.
Fixed Full Scan by replacing the broken GetAll-style scan with a slower page-by-page full scan fallback, which successfully processed items.
Patched Auctionator’s selling-price flow so selecting an item on the Selling tab now correctly queries the AH and updates the unit price based on current auctions.
Added debug slash commands like /a253state, /a253sell, and /a253sellbox to confirm the addon was finding rows even when the UI was not displaying them.
Found that the remaining Selling tab issue was UI/render/layout, not scan/data: the addon had rows, but the embedded results table was not painting correctly.
Built a custom Selling-tab auction rows overlay that displays competing auctions directly in the blank lower box.
Iterated that overlay through v6/v7 to fit it into the Selling tab box, avoid the broken double-scrollbar UI, and hide when using the History view.
