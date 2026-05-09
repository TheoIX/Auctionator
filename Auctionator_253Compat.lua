-- Auctionator 2.5.3 compatibility patch v5
-- Load this AFTER Source_Classic\Manifest.xml in Auctionator.toc
--
-- Keep using the patched Scan.lua and patched Throttling.lua from the prior steps.
--
-- v5 changes:
--   1) Keeps the v2 full-scan fix: skip GetAll and use page-by-page scanning.
--   2) More aggressively patches the live Selling tab SearchDataProvider instance,
--      not only the mixin table. Some WoW clients copy mixin functions to frames
--      before this file loads, so patching only the mixin is not always enough.
--   3) Rebuilds the Selling tab current-auction result rows by item name when the
--      private/2.5.3 AH does not provide matching cleaned item links.
--   4) Treats missing seller/owner as "Unknown" so missing owner names do not stop
--      display or pricing.
--   5) Adds /a253state and /a253dump debug helpers.
--   6) Adds a dedicated Selling item listener so selecting an item always kicks
--      the current-auctions search, even if Auctionator's original RefreshBuying
--      event path does not fire on this 2.5.3/private server.

local COMPAT_VERSION = "v5"
local COMPAT_PREFIX = "|cffffd100Auctionator 2.5.3 compat " .. COMPAT_VERSION .. ":|r "

local function CompatMessage(msg)
  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.Message then
    Auctionator.Utilities.Message(COMPAT_PREFIX .. msg)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(COMPAT_PREFIX .. msg)
  end
end

local function LowerText(value)
  if value == nil then
    return nil
  end
  return string.lower(tostring(value))
end

local function NameFromLink(link)
  if link == nil then
    return nil
  end

  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.GetNameFromLink then
    local ok, name = pcall(Auctionator.Utilities.GetNameFromLink, link)
    if ok and name ~= nil and name ~= "" then
      return name
    end
  end

  local left = string.find(link, "[", 1, true)
  local right = string.find(link, "]", 1, true)
  if left ~= nil and right ~= nil and right > left then
    return string.sub(link, left + 1, right - 1)
  end

  return nil
end

local function HasClassicAuctionator()
  return Auctionator ~= nil and Auctionator.Constants ~= nil and Auctionator.Constants.AuctionItemInfo ~= nil
end

local function QueryAuctionatorPage(searchText, page)
  -- Older 2.5.3-compatible form:
  -- QueryAuctionItems(name, minLevel, maxLevel, page, usable, rarity, getAll)
  QueryAuctionItems(searchText or "", nil, nil, page or 0, nil, nil, false)
end

local function GetInfoValue(entry, keyName, fallbackIndex, defaultValue)
  if entry == nil or entry.info == nil then
    return defaultValue
  end

  local constants = Auctionator.Constants.AuctionItemInfo
  local value = nil
  if constants ~= nil and constants[keyName] ~= nil then
    value = entry.info[constants[keyName]]
  end
  if value == nil and fallbackIndex ~= nil then
    value = entry.info[fallbackIndex]
  end
  if value == nil then
    return defaultValue
  end
  return value
end

local function SafeToUnitPrice(entry)
  if entry == nil or entry.info == nil then
    return 0
  end

  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.ToUnitPrice then
    local ok, price = pcall(Auctionator.Utilities.ToUnitPrice, entry)
    if ok and price ~= nil then
      return price
    end
  end

  local qty = GetInfoValue(entry, "Quantity", 3, 0)
  local buyout = GetInfoValue(entry, "Buyout", 10, 0)
  if qty > 0 and buyout > 0 then
    return math.ceil(buyout / qty)
  end
  return 0
end

local function EntryName(entry)
  local name = nil
  if entry ~= nil and entry.info ~= nil then
    name = entry.info[1]
  end
  if (name == nil or name == "") and entry ~= nil and entry.itemLink ~= nil then
    name = NameFromLink(entry.itemLink)
  end
  return name
end

local function OwnerText(entry)
  local owner = GetInfoValue(entry, "Owner", 14, nil)
  if owner == nil or owner == "" or owner == UNKNOWNOBJECT or tostring(owner) == "nil" then
    return AUCTIONATOR_L_UNDERCUT_UNKNOWN or UNKNOWN or "Unknown"
  end
  return tostring(owner)
end

local function GetCleanItemString(link)
  if link == nil or Auctionator == nil or Auctionator.Search == nil or Auctionator.Search.GetCleanItemLink == nil then
    return nil
  end

  local ok, itemString = pcall(Auctionator.Search.GetCleanItemLink, link)
  if ok then
    return itemString
  end

  return nil
end

local function ResultMatchesSellingQuery(self, entry)
  if entry == nil then
    return false
  end

  -- Original Auctionator-style match: exact cleaned item link/string.
  local itemString = GetCleanItemString(entry.itemLink)
  if self.searchKey ~= nil and itemString ~= nil and itemString == self.searchKey then
    return true
  end

  -- Private/2.5.3 fallback: exact visible item name match.
  local entryName = LowerText(EntryName(entry))
  if self.compat253SearchName ~= nil and entryName == self.compat253SearchName then
    return true
  end

  -- Extra fallback: sometimes the query is just the name, and the entry has only name info.
  if self.compat253QueryName ~= nil and entryName == LowerText(self.compat253QueryName) then
    return true
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Buy/Selling data provider patch
-- ---------------------------------------------------------------------------
local COMPAT_BUY_EVENTS = nil

local function EnsureBuyEvents()
  if COMPAT_BUY_EVENTS == nil and HasClassicAuctionator() then
    COMPAT_BUY_EVENTS = {
      Auctionator.AH.Events.ScanResultsUpdate,
      Auctionator.AH.Events.ScanAborted,
    }
  end
  return COMPAT_BUY_EVENTS
end

local function CompatSetQuery(self, itemLink, forcedName)
  if self.Reset then
    self:Reset()
  end

  self.compat253OriginalItemLink = itemLink
  self.compat253SearchName = nil
  self.compat253QueryName = nil

  if itemLink == nil and (forcedName == nil or forcedName == "") then
    self.query = nil
    self.searchKey = nil
    return
  end

  local clean = GetCleanItemString(itemLink)
  self.searchKey = clean

  local name = forcedName or NameFromLink(itemLink)
  if name == nil or name == "" then
    name = itemLink
  end

  self.compat253QueryName = name
  self.compat253SearchName = LowerText(name)

  self.query = {
    searchString = name,
    minLevel = nil,
    maxLevel = nil,
    itemClassFilters = nil,
    isExact = false,
    quality = nil,
  }
end

local function CompatSetQueryFromItemInfo(self, itemInfo)
  local link = nil
  local name = nil

  if itemInfo ~= nil then
    link = itemInfo.itemLink
    name = itemInfo.itemName or itemInfo.name or NameFromLink(link)

    if (name == nil or name == "") and itemInfo.location ~= nil and C_Item ~= nil and C_Item.DoesItemExist and C_Item.DoesItemExist(itemInfo.location) then
      local item = Item:CreateFromItemLocation(itemInfo.location)
      if item ~= nil and item.GetItemName ~= nil then
        local ok, itemName = pcall(function() return item:GetItemName() end)
        if ok and itemName ~= nil and itemName ~= "" then
          name = itemName
        end
      end
    end
  end

  CompatSetQuery(self, link, name)
end

local function CompatImportAdditionalResults(self, results)
  results = results or {}
  self.allAuctions = self.allAuctions or {}

  local accepted = 0
  for _, entry in ipairs(results) do
    if ResultMatchesSellingQuery(self, entry) and SafeToUnitPrice(entry) ~= 0 then
      if entry.itemLink == nil then
        entry.itemLink = self.compat253OriginalItemLink
      end
      table.insert(self.allAuctions, entry)
      accepted = accepted + 1
    end
  end

  self.compat253LastAccepted = accepted
  self.compat253LastSeen = #results

  if self.PopulateAuctions then
    self:PopulateAuctions()
  end
end

local function CompatPopulateAuctions(self)
  if self.allAuctions == nil then
    self.allAuctions = {}
  end

  -- Reset the visible/result queue but preserve self.allAuctions.
  if AuctionatorDataProviderMixin and AuctionatorDataProviderMixin.Reset then
    AuctionatorDataProviderMixin.Reset(self)
  elseif self.Reset then
    self:Reset()
  end

  table.sort(self.allAuctions, function(a, b)
    local unitA = SafeToUnitPrice(a)
    local unitB = SafeToUnitPrice(b)
    if unitA == unitB then
      local stackA = GetInfoValue(a, "Quantity", 3, 0)
      local stackB = GetInfoValue(b, "Quantity", 3, 0)
      if stackA == stackB then
        return OwnerText(a) < OwnerText(b)
      end
      return stackA > stackB
    end
    return unitA < unitB
  end)

  local results = {}
  local playerName = GetUnitName and GetUnitName("player") or UnitName("player")

  for _, auction in ipairs(self.allAuctions) do
    local unitPrice = SafeToUnitPrice(auction)
    local stackPrice = GetInfoValue(auction, "Buyout", 10, 0)
    local stackSize = GetInfoValue(auction, "Quantity", 3, 0)
    local bidAmount = GetInfoValue(auction, "BidAmount", 11, 0)
    local owner = OwnerText(auction)
    local itemLink = auction.itemLink or self.compat253OriginalItemLink

    if unitPrice ~= nil and unitPrice > 0 and stackPrice ~= nil and stackPrice > 0 and stackSize ~= nil and stackSize > 0 then
      local isOwned = playerName ~= nil and owner == playerName
      local newEntry = {
        itemLink = itemLink,
        unitPrice = unitPrice,
        stackPrice = stackPrice,
        stackSize = stackSize,
        numStacks = 1,
        isOwned = isOwned,
        otherSellers = owner,
        bidAmount = bidAmount,
        isSelected = false,
        notReady = false,
        query = auction.query or self.query,
        page = auction.page or 0,
      }

      if isOwned then
        newEntry.otherSellers = GREEN_FONT_COLOR:WrapTextInColorCode(AUCTIONATOR_L_YOU)
        newEntry.isOwnedText = AUCTIONATOR_L_UNDERCUT_YES
      else
        newEntry.isOwnedText = ""
      end

      if Auctionator.Utilities.SetStacksText then
        Auctionator.Utilities.SetStacksText(newEntry)
      else
        newEntry.availablePretty = tostring(stackSize)
      end

      local prevResult = results[#results]
      if prevResult ~= nil and
         prevResult.unitPrice == newEntry.unitPrice and
         prevResult.stackSize == newEntry.stackSize and
         prevResult.itemLink == newEntry.itemLink and
         prevResult.otherSellers == newEntry.otherSellers and
         prevResult.bidAmount == newEntry.bidAmount then
        prevResult.numStacks = prevResult.numStacks + 1
        if Auctionator.Utilities.SetStacksText then
          Auctionator.Utilities.SetStacksText(prevResult)
        end
      else
        if prevResult ~= nil then
          prevResult.nextEntry = newEntry
        end
        table.insert(results, newEntry)
      end
    end
  end

  self.compat253LastBuiltRows = #results

  if self.AppendEntries then
    self:AppendEntries(results, true)
  end

  -- 2.5.3/private-server compatibility: in this Selling-tab path the
  -- DataProvider frame sometimes does not process its queued rows quickly
  -- enough for the results listing to repaint. Process the queued rows now
  -- and explicitly nudge the visible Selling listing. This does not change
  -- the pricing logic; it only makes the lower current-auctions table render.
  if self.CheckForEntriesToProcess ~= nil then
    pcall(function() self:CheckForEntriesToProcess(0) end)
  elseif AuctionatorDataProviderMixin ~= nil and AuctionatorDataProviderMixin.CheckForEntriesToProcess ~= nil then
    pcall(function() AuctionatorDataProviderMixin.CheckForEntriesToProcess(self, 0) end)
  end

  self.compat253LastProviderCount = (self.GetCount ~= nil and self:GetCount()) or #(self.results or {})

  local sellingBuyFrame = AuctionatorSellingFrame and AuctionatorSellingFrame.BuyFrame
  if sellingBuyFrame ~= nil and sellingBuyFrame.SearchResultsListing ~= nil then
    if sellingBuyFrame.SearchResultsListing.Show ~= nil then
      sellingBuyFrame.SearchResultsListing:Show()
    end
    if sellingBuyFrame.SearchResultsListing.UpdateTable ~= nil then
      pcall(function() sellingBuyFrame.SearchResultsListing:UpdateTable() end)
    end
  end

  if #results > 0 then
    -- Update Auctionator's DB and the Selling tab price by focusing the cheapest row.
    if self.ReportNewMinPrice then
      pcall(function() self:ReportNewMinPrice() end)
    end

    results[1].isSelected = true
    Auctionator.EventBus:Fire(self, Auctionator.Buying.Events.AuctionFocussed, results[1])
  end
end

local function CompatRefreshQuery(self)
  if self.Reset then
    self:Reset()
  end

  if self.query ~= nil then
    if Auctionator.AH and Auctionator.AH.AbortQuery then
      Auctionator.AH.AbortQuery()
    end

    if self.onSearchStarted then
      self.onSearchStarted()
    end

    self.allAuctions = {}
    self.gotAllResults = false

    local events = EnsureBuyEvents()
    if events ~= nil then
      Auctionator.EventBus:Register(self, events)
    end

    Auctionator.AH.QueryAuctionItems(self.query)
  end
end

local function PatchProvider(provider)
  if provider == nil or provider.compat253V5ProviderPatched then
    return false
  end

  provider.compat253V5ProviderPatched = true
  provider.SetQuery = CompatSetQuery
  provider.Compat253SetQueryFromItemInfo = CompatSetQueryFromItemInfo
  provider.ImportAdditionalResults = CompatImportAdditionalResults
  provider.PopulateAuctions = CompatPopulateAuctions
  provider.RefreshQuery = CompatRefreshQuery
  return true
end

local function PatchBuyFrame(frame)
  if frame == nil then
    return false
  end

  local patched = false
  if frame.SearchDataProvider ~= nil then
    patched = PatchProvider(frame.SearchDataProvider) or patched
  end

  if not frame.compat253V5SellingReceivePatched and Auctionator and Auctionator.Selling and Auctionator.Selling.Events then
    frame.compat253V5SellingReceivePatched = true
    local oldReceive = frame.ReceiveEvent

    frame.ReceiveEvent = function(self, eventName, eventData, ...)
      if eventName == Auctionator.Selling.Events.RefreshBuying and self.SearchDataProvider ~= nil then
        self:Reset()

        if self.HistoryDataProvider ~= nil and eventData ~= nil then
          self.HistoryDataProvider:SetItemLink(eventData.itemLink)
        end

        PatchProvider(self.SearchDataProvider)
        self.SearchDataProvider:Compat253SetQueryFromItemInfo(eventData)
        self.SearchDataProvider:SetRequestAllResults(Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ALWAYS_LOAD_MORE))
        self.SearchDataProvider:RefreshQuery()

        self.RefreshButton:Enable()
        self.HistoryButton:Enable()
      elseif oldReceive ~= nil then
        oldReceive(self, eventName, eventData, ...)
      end
    end

    patched = true
  end

  return patched
end

local function PatchKnownFrames()
  local count = 0

  if AuctionatorSellingFrame ~= nil then
    if PatchBuyFrame(AuctionatorSellingFrame.BuyFrame) then
      count = count + 1
    end
  end

  if AuctionatorShoppingListFrame ~= nil then
    if PatchBuyFrame(AuctionatorShoppingListFrame.BuyFrame) then
      count = count + 1
    end
  end

  return count
end

if HasClassicAuctionator() and AuctionatorBuyAuctionsDataProviderMixin ~= nil then
  AuctionatorBuyAuctionsDataProviderMixin.SetQuery = CompatSetQuery
  AuctionatorBuyAuctionsDataProviderMixin.Compat253SetQueryFromItemInfo = CompatSetQueryFromItemInfo
  AuctionatorBuyAuctionsDataProviderMixin.ImportAdditionalResults = CompatImportAdditionalResults
  AuctionatorBuyAuctionsDataProviderMixin.PopulateAuctions = CompatPopulateAuctions
  AuctionatorBuyAuctionsDataProviderMixin.RefreshQuery = CompatRefreshQuery
end

if AuctionatorBuyFrameMixinForSelling ~= nil and not AuctionatorBuyFrameMixinForSelling.compat253V5MixinPatched then
  AuctionatorBuyFrameMixinForSelling.compat253V5MixinPatched = true
  local oldSellingReceive = AuctionatorBuyFrameMixinForSelling.ReceiveEvent

  function AuctionatorBuyFrameMixinForSelling:ReceiveEvent(eventName, eventData, ...)
    if eventName == Auctionator.Selling.Events.RefreshBuying and self.SearchDataProvider ~= nil then
      self:Reset()

      if self.HistoryDataProvider ~= nil and eventData ~= nil then
        self.HistoryDataProvider:SetItemLink(eventData.itemLink)
      end

      PatchProvider(self.SearchDataProvider)
      self.SearchDataProvider:Compat253SetQueryFromItemInfo(eventData)
      self.SearchDataProvider:SetRequestAllResults(Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ALWAYS_LOAD_MORE))
      self.SearchDataProvider:RefreshQuery()

      self.RefreshButton:Enable()
      self.HistoryButton:Enable()
    else
      oldSellingReceive(self, eventName, eventData, ...)
    end
  end
end

-- Patch live frames after they are created. Some XML mixins are copied onto frame
-- instances before this compatibility file runs, so repeat lightly during login/AH open.
local patchAttempts = 0
local function DelayedPatchKnownFrames()
  patchAttempts = patchAttempts + 1
  PatchKnownFrames()
  if patchAttempts < 20 then
    C_Timer.After(0.5, DelayedPatchKnownFrames)
  end
end
C_Timer.After(0, DelayedPatchKnownFrames)


-- ---------------------------------------------------------------------------
-- Selling tab forced search kicker
-- ---------------------------------------------------------------------------
local function CompatKickSellingSearch(itemInfo, reason)
  if not HasClassicAuctionator() then
    return false
  end

  local buyFrame = nil
  if AuctionatorSellingFrame ~= nil and AuctionatorSellingFrame.BuyFrame ~= nil then
    buyFrame = AuctionatorSellingFrame.BuyFrame
  end

  if buyFrame == nil or buyFrame.SearchDataProvider == nil then
    return false
  end

  PatchBuyFrame(buyFrame)
  PatchProvider(buyFrame.SearchDataProvider)

  local provider = buyFrame.SearchDataProvider
  provider.compat253LastKickReason = reason or "unknown"
  provider.compat253LastKickTime = GetTime and GetTime() or 0

  if buyFrame.Reset ~= nil then
    buyFrame:Reset()
  end

  if buyFrame.HistoryDataProvider ~= nil and itemInfo ~= nil and itemInfo.itemLink ~= nil then
    pcall(function()
      buyFrame.HistoryDataProvider:SetItemLink(itemInfo.itemLink)
    end)
  end

  provider:Compat253SetQueryFromItemInfo(itemInfo)

  if provider.query == nil then
    provider.compat253LastKickError = "no query from itemInfo"
    return false
  end

  if provider.SetRequestAllResults ~= nil then
    provider:SetRequestAllResults(Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ALWAYS_LOAD_MORE))
  end

  provider:RefreshQuery()

  if buyFrame.RefreshButton ~= nil then
    buyFrame.RefreshButton:Enable()
  end
  if buyFrame.HistoryButton ~= nil then
    buyFrame.HistoryButton:Enable()
  end

  provider.compat253LastKickError = nil
  return true
end

local Compat253SellingListener = {}
function Compat253SellingListener:ReceiveEvent(eventName, eventData, ...)
  if not HasClassicAuctionator() then
    return
  end

  if eventName == Auctionator.Selling.Events.BagItemClicked or
     eventName == Auctionator.Selling.Events.RefreshBuying then
    local itemInfo = eventData
    C_Timer.After(0.05, function()
      local ok = CompatKickSellingSearch(itemInfo, eventName)
      if ok then
        local provider = AuctionatorSellingFrame and AuctionatorSellingFrame.BuyFrame and AuctionatorSellingFrame.BuyFrame.SearchDataProvider
        if provider ~= nil then
          provider.compat253LastListenerEvent = eventName
        end
      end
    end)
  end
end

if HasClassicAuctionator() and Auctionator.EventBus ~= nil and Auctionator.Selling ~= nil and Auctionator.Selling.Events ~= nil then
  Auctionator.EventBus:Register(Compat253SellingListener, {
    Auctionator.Selling.Events.BagItemClicked,
    Auctionator.Selling.Events.RefreshBuying,
  })
end

-- ---------------------------------------------------------------------------
-- Full Scan page-by-page fallback, no GetAll request at all
-- ---------------------------------------------------------------------------
if HasClassicAuctionator() and AuctionatorFullScanFrameMixin ~= nil then
  local FULL_SCAN_EVENTS = {
    "AUCTION_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_CLOSED",
  }

  local MAX_RESULTS_PER_PAGE = Auctionator.Constants.MaxResultsPerPage or 50

  function AuctionatorFullScanFrameMixin:CanInitiate()
    if CanSendAuctionQuery == nil then
      return true
    end

    local canSend = CanSendAuctionQuery()
    return canSend == true
  end

  function AuctionatorFullScanFrameMixin:RegisterForEvents()
    FrameUtil.RegisterFrameForEvents(self, FULL_SCAN_EVENTS)
  end

  function AuctionatorFullScanFrameMixin:UnregisterForEvents()
    FrameUtil.UnregisterFrameForEvents(self, FULL_SCAN_EVENTS)
  end

  function AuctionatorFullScanFrameMixin:Compat253WaitThenQueryPage()
    if not self.inProgress or not self.compat253PagedScan then
      return
    end

    if CanSendAuctionQuery ~= nil then
      local canSend = CanSendAuctionQuery()
      if not canSend then
        C_Timer.After(0.25, function()
          self:Compat253WaitThenQueryPage()
        end)
        return
      end
    end

    QueryAuctionatorPage("", self.compat253CurrentPage or 0)
  end

  local function InsertAuctionData(self, info, link, onDone)
    if info == nil or link == nil then
      onDone()
      return
    end

    local quantity = info[Auctionator.Constants.AuctionItemInfo.Quantity] or info[3] or 0
    local buyout = info[Auctionator.Constants.AuctionItemInfo.Buyout] or info[10] or 0

    if quantity <= 0 or buyout <= 0 then
      onDone()
      return
    end

    Auctionator.Utilities.DBKeyFromLink(link, function(dbKeys)
      table.insert(self.scanData, {
        auctionInfo = info,
        itemLink = link,
      })
      table.insert(self.dbKeysMapping, dbKeys or {})
      onDone()
    end)
  end

  function AuctionatorFullScanFrameMixin:Compat253CacheCurrentPage(callback)
    local total = GetNumAuctionItems("list") or 0

    if total == 0 then
      callback(0)
      return
    end

    local pending = 0
    local finishedLoop = false

    local function OneDone()
      pending = pending - 1
      if finishedLoop and pending <= 0 then
        callback(total)
      end
    end

    for index = 1, total do
      local info = { GetAuctionItemInfo("list", index) }
      local link = GetAuctionItemLink("list", index)

      pending = pending + 1

      if link ~= nil then
        InsertAuctionData(self, info, link, OneDone)
      else
        OneDone()
      end
    end

    finishedLoop = true
    if pending <= 0 then
      callback(total)
    end
  end

  function AuctionatorFullScanFrameMixin:Compat253ProcessPage()
    if not self.inProgress or not self.compat253PagedScan then
      return
    end

    local page = self.compat253CurrentPage or 0

    Auctionator.EventBus:Fire(
      self,
      Auctionator.FullScan.Events.ScanProgress,
      math.min(0.95, 0.02 + (page / 45))
    )

    self:Compat253CacheCurrentPage(function(pageCount)
      if not self.inProgress then
        return
      end

      self.compat253ScannedPages = (self.compat253ScannedPages or 0) + 1
      self.compat253ScannedAuctions = (self.compat253ScannedAuctions or 0) + pageCount

      if pageCount < MAX_RESULTS_PER_PAGE then
        self:EndProcessing()
      else
        self.compat253CurrentPage = page + 1
        C_Timer.After(0.15, function()
          self:Compat253WaitThenQueryPage()
        end)
      end
    end)
  end

  function AuctionatorFullScanFrameMixin:InitiateScan()
    if not self:CanInitiate() then
      Auctionator.Utilities.Message(AUCTIONATOR_L_SERVER_TOOK_TOO_LONG or "Auction house is not ready yet.")
      return
    end

    Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanStart)

    self.state.TimeOfLastGetAllScan = time()
    self.inProgress = true
    self.compat253PagedScan = true
    self.compat253CurrentPage = 0
    self.compat253ScannedPages = 0
    self.compat253ScannedAuctions = 0

    self:ResetData()
    self:RegisterForEvents()

    if not ITEM_QUALITY_COLORS[-1] then
      ITEM_QUALITY_COLORS[-1] = {r=0, b=0, g=0}
    end

    CompatMessage("starting slower page-by-page scan; GetAll is skipped on this client/server.")
    Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanProgress, 0.01)
    self:Compat253WaitThenQueryPage()
  end

  function AuctionatorFullScanFrameMixin:OnEvent(event, ...)
    if event == "AUCTION_ITEM_LIST_UPDATE" then
      if self.compat253PagedScan then
        self:Compat253ProcessPage()
      end
    elseif event == "AUCTION_HOUSE_CLOSED" then
      self:UnregisterForEvents()

      if self.inProgress then
        self.inProgress = false
        self:ResetData()

        Auctionator.Utilities.Message(
          AUCTIONATOR_L_FULL_SCAN_FAILED .. " " .. self:NextScanMessage()
        )
        Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanFailed)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Debug helpers
-- ---------------------------------------------------------------------------
SLASH_AUCTIONATOR253DUMP1 = "/a253dump"
SlashCmdList["AUCTIONATOR253DUMP"] = function()
  local n = GetNumAuctionItems("list") or 0
  DEFAULT_CHAT_FRAME:AddMessage(COMPAT_PREFIX .. "AH list rows: " .. tostring(n))

  local max = math.min(n, 10)
  for i = 1, max do
    local info = { GetAuctionItemInfo("list", i) }
    local link = GetAuctionItemLink("list", i)
    local name = info[1] or NameFromLink(link) or "?"
    local qty = info[Auctionator.Constants.AuctionItemInfo.Quantity] or info[3] or 0
    local buyout = info[Auctionator.Constants.AuctionItemInfo.Buyout] or info[10] or 0
    local owner = info[Auctionator.Constants.AuctionItemInfo.Owner] or info[14] or "nil"
    DEFAULT_CHAT_FRAME:AddMessage(i .. ": " .. tostring(name) .. " qty=" .. tostring(qty) .. " buyout=" .. tostring(buyout) .. " owner=" .. tostring(owner) .. " link=" .. tostring(link))
  end
end


SLASH_AUCTIONATOR253SELL1 = "/a253sell"
SlashCmdList["AUCTIONATOR253SELL"] = function()
  local itemInfo = nil

  if AuctionatorSellingFrame ~= nil and AuctionatorSellingFrame.SaleItemFrame ~= nil then
    itemInfo = AuctionatorSellingFrame.SaleItemFrame.itemInfo
  end

  if itemInfo == nil then
    local name = GetAuctionSellItemInfo and GetAuctionSellItemInfo()
    if name ~= nil and name ~= "" then
      itemInfo = { itemName = name, name = name }
    end
  end

  if itemInfo == nil then
    CompatMessage("no selected selling item found for manual search.")
    return
  end

  if CompatKickSellingSearch(itemInfo, "manual /a253sell") then
    CompatMessage("manual selling search started for " .. tostring(itemInfo.itemName or itemInfo.name or NameFromLink(itemInfo.itemLink) or itemInfo.itemLink or "item"))
  else
    CompatMessage("manual selling search could not start; run /a253state.")
  end
end

SLASH_AUCTIONATOR253STATE1 = "/a253state"
SlashCmdList["AUCTIONATOR253STATE"] = function()
  local provider = nil
  if AuctionatorSellingFrame ~= nil and AuctionatorSellingFrame.BuyFrame ~= nil then
    provider = AuctionatorSellingFrame.BuyFrame.SearchDataProvider
  end

  DEFAULT_CHAT_FRAME:AddMessage(COMPAT_PREFIX .. "provider=" .. tostring(provider ~= nil) .. " patched=" .. tostring(provider ~= nil and provider.compat253V5ProviderPatched))
  if provider ~= nil then
    DEFAULT_CHAT_FRAME:AddMessage(COMPAT_PREFIX .. "query=" .. tostring(provider.compat253QueryName) .. " seen=" .. tostring(provider.compat253LastSeen) .. " accepted=" .. tostring(provider.compat253LastAccepted) .. " rows=" .. tostring(provider.compat253LastBuiltRows) .. " providerCount=" .. tostring(provider.compat253LastProviderCount))
    DEFAULT_CHAT_FRAME:AddMessage(COMPAT_PREFIX .. "kick=" .. tostring(provider.compat253LastKickReason) .. " listener=" .. tostring(provider.compat253LastListenerEvent) .. " error=" .. tostring(provider.compat253LastKickError))
  end
end

CompatMessage("loaded. Full Scan skips GetAll; Selling item listener enabled. Use /a253sell to force current-item search.")
