AuctionatorSellingTabMixin = {}

-- TBC/2.5.3 Selling tab layout patch
-- Goal: hide Auctionator's internal bag browser and let the "current auctions"
-- results list use the full width under the posting controls.

local LAYOUT_UPDATE_FRAMES = 30

local function HideFrame(frame)
  if frame ~= nil then
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
    frame:SetSize(1, 1)
  end
end

local function SafeSetPoint(frame, ...)
  if frame ~= nil then
    frame:ClearAllPoints()
    frame:SetPoint(...)
  end
end

local function RefreshResultsListing(listing)
  if listing == nil then
    return
  end

  -- Re-anchor the table pieces after the parent has its final size.
  if listing.HeaderContainer ~= nil then
    listing.HeaderContainer:ClearAllPoints()
    listing.HeaderContainer:SetPoint("TOPLEFT", listing, "TOPLEFT", 0, -7)
    listing.HeaderContainer:SetPoint("RIGHT", listing, "RIGHT", 0, 0)
  end

  if listing.ScrollFrame ~= nil and listing.HeaderContainer ~= nil then
    listing.ScrollFrame:ClearAllPoints()
    listing.ScrollFrame:SetPoint("TOPLEFT", listing.HeaderContainer, "BOTTOMLEFT", 15, -3)
    listing.ScrollFrame:SetPoint("RIGHT", listing.HeaderContainer, "RIGHT", -2, 0)
    listing.ScrollFrame:SetPoint("BOTTOM", listing, "BOTTOMRIGHT", 0, 4)
  end

  -- Force Auctionator's table builder to re-arrange columns after resizing.
  if listing.isInitialized then
    if listing.UpdateForHiding ~= nil then
      listing:UpdateForHiding()
    elseif listing.tableBuilder ~= nil and listing.tableBuilder.Arrange ~= nil then
      listing.tableBuilder:Arrange()
    end

    if listing.UpdateTable ~= nil then
      listing:UpdateTable()
    end
  end
end

function AuctionatorSellingTabMixin:ApplyFullWidthSellingLayout()
  -- The built-in Auctionator bag panel is the part that crushes the selling
  -- results table on 2.5.3. We hide it and use normal WoW bags/right-click
  -- selection instead.
  HideFrame(self.BagListing)
  HideFrame(self.BagInset)

  if self.BuyFrame ~= nil then
    self.BuyFrame:ClearAllPoints()
    self.BuyFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -150)
    self.BuyFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -16, 38)
    self.BuyFrame:Show()

    if self.BuyFrame.SearchResultsListing ~= nil then
      self.BuyFrame.SearchResultsListing:ClearAllPoints()
      self.BuyFrame.SearchResultsListing:SetPoint("TOPLEFT", self.BuyFrame, "TOPLEFT", 4, 0)
      self.BuyFrame.SearchResultsListing:SetPoint("BOTTOMRIGHT", self.BuyFrame, "BOTTOMRIGHT", -28, 0)
    end

    if self.BuyFrame.HistoryResultsListing ~= nil then
      self.BuyFrame.HistoryResultsListing:ClearAllPoints()
      self.BuyFrame.HistoryResultsListing:SetPoint("TOPLEFT", self.BuyFrame, "TOPLEFT", 4, 0)
      self.BuyFrame.HistoryResultsListing:SetPoint("BOTTOMRIGHT", self.BuyFrame, "BOTTOMRIGHT", -28, 0)
    end

    if self.BuyFrame.Inset ~= nil and self.BuyFrame.SearchResultsListing ~= nil then
      self.BuyFrame.Inset:ClearAllPoints()
      self.BuyFrame.Inset:SetPoint("TOPLEFT", self.BuyFrame.SearchResultsListing, "TOPLEFT", -10, -25)
      self.BuyFrame.Inset:SetPoint("BOTTOMRIGHT", self.BuyFrame.SearchResultsListing, "BOTTOMRIGHT", 8, 2)
    end

    if self.BuyFrame.LoadAllPagesButton ~= nil and self.BuyFrame.Inset ~= nil then
      self.BuyFrame.LoadAllPagesButton:ClearAllPoints()
      self.BuyFrame.LoadAllPagesButton:SetPoint("BOTTOMLEFT", self.BuyFrame.Inset)
      self.BuyFrame.LoadAllPagesButton:SetPoint("TOPRIGHT", self.BuyFrame.Inset, "BOTTOMRIGHT", 0, 20)
    end

    if self.BuyFrame.HistoryButton ~= nil and self.BuyFrame.SearchResultsListing ~= nil then
      self.BuyFrame.HistoryButton:ClearAllPoints()
      self.BuyFrame.HistoryButton:SetPoint("TOP", self.BuyFrame.SearchResultsListing, "BOTTOM", 0, 0)
      self.BuyFrame.HistoryButton:SetPoint("LEFT", self.BuyFrame.SearchResultsListing, "LEFT", -8, 10)
    end

    if self.BuyFrame.CancelButton ~= nil and self.BuyFrame.SearchResultsListing ~= nil then
      self.BuyFrame.CancelButton:ClearAllPoints()
      self.BuyFrame.CancelButton:SetPoint("TOP", self.BuyFrame.SearchResultsListing, "BOTTOM", 0, 0)
      self.BuyFrame.CancelButton:SetPoint("RIGHT", self.BuyFrame.SearchResultsListing, "RIGHT", -8, 10)
    end

    if self.BuyFrame.BuyButton ~= nil and self.BuyFrame.CancelButton ~= nil then
      self.BuyFrame.BuyButton:ClearAllPoints()
      self.BuyFrame.BuyButton:SetPoint("LEFT", self.BuyFrame.CancelButton, "LEFT", -100, 0)
      self.BuyFrame.BuyButton:SetPoint("BOTTOMRIGHT", self.BuyFrame.CancelButton, "BOTTOMLEFT", 0, 0)
    end

    if self.BuyFrame.RefreshButton ~= nil and self.BuyFrame.BuyButton ~= nil then
      self.BuyFrame.RefreshButton:ClearAllPoints()
      self.BuyFrame.RefreshButton:SetPoint("BOTTOMRIGHT", self.BuyFrame.BuyButton, "BOTTOMLEFT", 0, 0)
    end

    RefreshResultsListing(self.BuyFrame.SearchResultsListing)
    RefreshResultsListing(self.BuyFrame.HistoryResultsListing)
  end
end

function AuctionatorSellingTabMixin:QueueLayoutRefresh()
  self._sellingPatchFramesLeft = LAYOUT_UPDATE_FRAMES
end

function AuctionatorSellingTabMixin:OnLoad()
  -- Do not initialize the internal Auctionator bag listing. It is the broken
  -- part of the layout on this 2.5.3 setup. Normal bag right-click selling is
  -- still handled by Source_Classic/Selling/Hooks.lua.
  self:ApplyFullWidthSellingLayout()

  self.BuyFrame:Init()

  self:ApplyFullWidthSellingLayout()
  self:QueueLayoutRefresh()
end

function AuctionatorSellingTabMixin:OnShow()
  self:ApplyFullWidthSellingLayout()
  self:QueueLayoutRefresh()
end

function AuctionatorSellingTabMixin:OnUpdate()
  if self._sellingPatchFramesLeft == nil or self._sellingPatchFramesLeft <= 0 then
    return
  end

  self._sellingPatchFramesLeft = self._sellingPatchFramesLeft - 1
  self:ApplyFullWidthSellingLayout()
end

function AuctionatorSellingTabMixin:OnHide()
  self._sellingPatchFramesLeft = 0
end

function AuctionatorSellingTabMixin:ApplyHiding()
  -- Kept for compatibility with older Auctionator code paths.
  self:ApplyFullWidthSellingLayout()
end
