AuctionatorAHScanFrameMixin = {}

local SCAN_EVENTS = {
  "AUCTION_ITEM_LIST_UPDATE",
}

-- 2.5.3 / private-core compatibility:
-- Auctionator 9.2.31-bcc was written for the newer Classic AH wrapper that can
-- pass exactMatch and itemClassFilters into QueryAuctionItems. Some 2.5.3 cores
-- appear to accept the Lua call but never return AUCTION_ITEM_LIST_UPDATE when
-- those newer trailing args are present.
--
-- So this patch intentionally uses the older, safer 7-argument call:
--   QueryAuctionItems(name, minLevel, maxLevel, page, usable, rarity, getAll)
-- Auctionator still filters/group/sorts the returned rows itself afterward.
local function ParamsForBlizzardAPI(query, page)
  return query.searchString,
         query.minLevel,
         query.maxLevel,
         page,
         false,
         query.quality,
         false
end

-- Avoid setting the hidden "unitprice" sort before querying. Some older/private
-- 2.5.3 AH implementations do not handle that sort mode cleanly.
local function Auctionator_SafeAuctionSort()
  -- Intentionally left blank for 2.5.3 compatibility.
end

function AuctionatorAHScanFrameMixin:OnLoad()
  self.scanRunning = false
  Auctionator.EventBus:RegisterSource(self, "AuctionatorAHScanFrameMixin")
end

function AuctionatorAHScanFrameMixin:IsOnLastPage()
  Auctionator.Debug.Message("AuctionatorAHScanFrameMixin:IsOnLastPage()")

  --Loaded all the terms from API
  return (
    (self.endPage ~= -1 and self.nextPage > self.endPage) or
    GetNumAuctionItems("list") < Auctionator.Constants.MaxResultsPerPage
  )
end

function AuctionatorAHScanFrameMixin:GotAllOwners()
  local result = true
  local allAuctions = Auctionator.AH.DumpAuctions("list")
  for _, auction in ipairs(allAuctions) do
    result = result and auction.info[Auctionator.Constants.AuctionItemInfo.Owner] ~= nil
  end

  return result
end

function AuctionatorAHScanFrameMixin:OnEvent(eventName, ...)
  -- Patch Fix 2: do not wait for every owner name before processing.
  -- Some private cores delay or omit owner names, which leaves Auctionator stuck
  -- on "Scanning page 1" forever.
  if eventName == "AUCTION_ITEM_LIST_UPDATE" and self.waitingOnPage and self.sentQuery then
    self.waitingOnPage = false
    self:ProcessSearchResults()
  end
end

function AuctionatorAHScanFrameMixin:StartQuery(query, startPage, endPage)
  if self.scanRunning then
    error("Scan already running")
  end
  self:RegisterEvents()

  self.scanRunning = true

  self.nextPage = startPage
  self.endPage = endPage
  self.query = query
  self:DoNextSearchQuery()
end

function AuctionatorAHScanFrameMixin:AbortQuery()
  if self.scanRunning then
    Auctionator.AH.Queue:Remove(self.lastQueuedItem)
    self.scanRunning = false
    self:UnregisterEvents()
    Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanAborted)
  end
end

function AuctionatorAHScanFrameMixin:DoNextSearchQuery()
  local page = self.nextPage
  self.sentQuery = false

  self.lastQueuedItem = function()
    if not self.scanRunning then
      return
    end

    self.sentQuery = true
    Auctionator_SafeAuctionSort()
    QueryAuctionItems(ParamsForBlizzardAPI(self.query, page))

    -- Last-resort timeout: if the server/client does not fire
    -- AUCTION_ITEM_LIST_UPDATE to the addon, process whatever is available so
    -- the scan cannot stay stuck forever.
    if C_Timer and C_Timer.After then
      C_Timer.After(4, function()
        if self.scanRunning and self.waitingOnPage and self.sentQuery and (self.nextPage - 1) == page then
          self.waitingOnPage = false
          self:ProcessSearchResults()
        end
      end)
    end
  end

  Auctionator.AH.Queue:Enqueue(self.lastQueuedItem)

  self.waitingOnPage = true
  self.nextPage = self.nextPage + 1

  Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanPageStart, page)
end

function AuctionatorAHScanFrameMixin:ProcessSearchResults()
  Auctionator.Debug.Message("AuctionatorAHScanFrameMixin:ProcessSearchResults()")

  local results = self:GetCurrentPage()

  if self:IsOnLastPage() then
    self.scanRunning = false
    self:UnregisterEvents()
  else
    self:DoNextSearchQuery()
  end
  Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanResultsUpdate, results, not self.scanRunning)
end

function AuctionatorAHScanFrameMixin:GetCurrentPage()
  local results = Auctionator.AH.DumpAuctions("list")
  for _, entry in ipairs(results) do
    entry.query = self.query
    entry.page = self.nextPage - 1
  end

  return results
end

function AuctionatorAHScanFrameMixin:RegisterEvents()
  FrameUtil.RegisterFrameForEvents(self, SCAN_EVENTS)
end

function AuctionatorAHScanFrameMixin:UnregisterEvents()
  FrameUtil.UnregisterFrameForEvents(self, SCAN_EVENTS)
end
