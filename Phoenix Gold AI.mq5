//+------------------------------------------------------------------+
//|                                              Phoenix Gold AI.mq5 |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Phoenix Gold AI is an institutional-grade, multi-timeframe      |
//| Expert Advisor for MetaTrader 5, blending Smart Money Concepts   |
//| (SMC) with advanced technical indicators for premium XAUUSD entry. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"

// Include Modular Headers
#include "Logger.mqh"
#include "Utilities.mqh"
#include "SessionFilter.mqh"
#include "NewsFilter.mqh"
#include "RiskManager.mqh"
#include "MoneyManager.mqh"
#include "IndicatorManager.mqh"
#include "SmartMoney.mqh"
#include "SignalEngine.mqh"
#include "TradeManager.mqh"
#include "Dashboard.mqh"
#include "Reports.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "--- RISK & MONEY MANAGEMENT ---"
input ENUM_LOT_SIZING_MODE InpLotMode        = LOT_MODE_DYNAMIC_RISK; // Lot Sizing Mode
input double               InpFixedLotSize    = 0.1;                  // Fixed Lot Size (Fixed Mode)
input double               InpRiskPercent     = 1.0;                  // Risk Percent per Trade
input double               InpAtrMultiplier   = 2.0;                  // ATR SL Multiplier (ATR Mode)
input double               InpMaxDailyDD      = 5.0;                  // Max Daily Drawdown %
input double               InpMaxWeeklyDD     = 8.0;                  // Max Weekly Drawdown %
input double               InpMaxMonthlyDD    = 10.0;                 // Max Monthly Drawdown %
input int                  InpMaxTradesPerDay = 5;                    // Max Trades Per Day
input double               InpMaxExposure     = 2.0;                  // Max Lot Exposure
input double               InpMinMarginLevel  = 200.0;                // Min Margin Level %
input int                  InpMaxConsecLosses = 3;                    // Max Consecutive Losses
input double               InpMaxFloatLossPct = 2.0;                  // Max Floating Loss %

input group "--- TRADE EXECUTION & LIMITS ---"
input ulong                InpMagicNumber     = 991199;               // Magic Number
input int                  InpSlippage        = 30;                   // Slippage (Points)
input double               InpMaxSpread       = 25.0;                 // Max Spread (Points)

input group "--- SESSION FILTER ---"
input string               InpAsiaStart       = "00:00";              // Asian Session Start
input string               InpAsiaEnd         = "08:00";              // Asian Session End
input string               InpLondonStart     = "09:00";              // London Session Start
input string               InpLondonEnd       = "18:00";              // London Session End
input string               InpNYStart         = "15:00";              // New York Session Start
input string               InpNYEnd           = "23:59";              // New York Session End
input string               InpSydneyStart     = "23:00";              // Sydney Session Start
input string               InpSydneyEnd       = "07:00";              // Sydney Session End

input group "--- NEWS FILTER ---"
input bool                 InpUseNewsFilter   = true;                 // Enable News Filter
input bool                 InpNewsMediumImpact= false;                 // Filter Medium Impact News
input bool                 InpNewsKeywords    = true;                  // Filter critical events only (NFP, FOMC etc)
input int                  InpNewsMinsBefore  = 30;                   // Pause Minutes Before News
input int                  InpNewsMinsAfter   = 30;                   // Resume Minutes After News

input group "--- SIGNAL SETTINGS ---"
input ENUM_SIGNAL_MODE     InpSignalMode      = SIGNAL_MODE_INSTITUTIONAL; // Entry Strategy
input double               InpMinRsiBuy       = 55.0;                 // Min RSI for BUY
input double               InpMaxRsiSell      = 45.0;                 // Max RSI for SELL
input double               InpMinAtrFilter    = 10.0;                 // Min ATR points (Filter Flat Market)
input bool                 InpUseH1Confirm    = true;                 // Confirm Trend on H1
input bool                 InpUseSmcZones     = true;                 // Buy in Discount / Sell in Premium

input group "--- BREAK EVEN SETTINGS ---"
input bool                 InpUseBreakEven    = true;                 // Enable Break Even
input double               InpBeActivation    = 150.0;                // Activation (Points)
input double               InpBeOffset        = 20.0;                 // Offset (Points above Entry)

input group "--- TRAILING STOP SETTINGS ---"
input bool                 InpUseTrailing     = true;                 // Enable Trailing Stop
input double               InpTrailStart      = 200.0;                // Activation (Points)
input double               InpTrailDistance   = 150.0;                // Distance (Points)
input double               InpTrailStep       = 20.0;                 // Step (Points)

input group "--- PARTIAL CLOSE SETTINGS ---"
input bool                 InpUsePartialClose = true;                 // Enable Partial Close
input double               InpPartialPct      = 0.50;                 // Close Volume %
input double               InpPartialTargetRR = 1.0;                  // Target Risk Reward Ratio

input group "--- TIME EXIT SETTINGS ---"
input bool                 InpUseFridayExit   = true;                 // Enable Friday Close
input string               InpFridayExitTime  = "22:00";              // Friday Close Time
input bool                 InpUseDurationExit = false;                 // Enable Max Duration Exit
input int                  InpMaxHoldingMins  = 1440;                 // Max Holding Duration (Mins)

//+------------------------------------------------------------------+
//| Global Manager Instances                                         |
//+------------------------------------------------------------------+
CSessionFilter     Sessions;
CNewsFilter        News;
CRiskManager       Risk;
CMoneyManager      Money;
CIndicatorManager  Indicators;
CSmartMoney        SMC;
CSignalEngine      Signal;
CTradeManager      Trade;
CDashboard         HUD;
CReports           Reports;

// Caches for execution control
datetime           m_last_bar_time = 0;

// Helper to check for new bar opening
bool               IsNewBar();
// Format the EA state for the HUD
string             GetTradingStatusString(bool &out_is_active);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Strict Symbol Validation: XAUUSD/GOLD only
   string symbol = _Symbol;
   StringToUpper(symbol);
   if(StringFind(symbol, "XAUUSD") < 0 && StringFind(symbol, "GOLD") < 0)
   {
      Alert("[PhoenixGoldAI] Critical Error: This EA is coded specifically for XAUUSD/GOLD pairs!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // 2. Strict Timeframe Validation: M15 only
   if(_Period != PERIOD_M15)
   {
      Alert("[PhoenixGoldAI] Critical Error: This EA must run on the M15 timeframe!");
      return(INIT_PARAMETERS_INCORRECT);
   }

   Logger.Info("Initializing Phoenix Gold AI EA...");

   // 3. Configure Managers
   Sessions.SetSessions(InpAsiaStart, InpAsiaEnd, InpLondonStart, InpLondonEnd, InpNYStart, InpNYEnd, InpSydneyStart, InpSydneyEnd);
   
   News.Configure(InpNewsMediumImpact, InpNewsKeywords);
   
   Risk.SetLimits(InpMaxDailyDD, InpMaxWeeklyDD, InpMaxMonthlyDD, InpMaxTradesPerDay, InpMaxExposure, InpMinMarginLevel);
   Risk.ConfigureRoadmapLimits(InpMagicNumber, InpMaxConsecLosses, InpMaxFloatLossPct);
   
   Money.SetSizingMode(InpLotMode, InpFixedLotSize, InpRiskPercent, InpAtrMultiplier);
   
   if(!Indicators.Init(_Symbol, PERIOD_M15, PERIOD_H1))
   {
      Logger.Error("Indicator handle creation failed. Initialization aborted.");
      return(INIT_FAILED);
   }
   
   SMC.Init(_Symbol, PERIOD_M15);
   
   Signal.Init(&Indicators, &SMC);
   Signal.Configure(InpSignalMode, InpMinRsiBuy, InpMaxRsiSell, InpMinAtrFilter, InpUseH1Confirm, InpUseSmcZones);
   
   Trade.Init(InpMagicNumber, InpSlippage, InpMaxSpread);
   Trade.ConfigureBreakEven(InpUseBreakEven, InpBeActivation, InpBeOffset);
   Trade.ConfigureTrailingStop(InpUseTrailing, InpTrailStart, InpTrailDistance, InpTrailStep);
   Trade.ConfigurePartialClose(InpUsePartialClose, InpPartialPct, InpPartialTargetRR);
   Trade.ConfigureTimeExit(InpUseFridayExit, InpFridayExitTime, InpUseDurationExit, InpMaxHoldingMins);
   
   Reports.Init(_Symbol, InpMagicNumber);
   
   HUD.Init(20, 50);

   // Establish 1-second refresh timer
   EventSetTimer(1);
   
   Logger.Info("Initialization Complete. EA loaded in SCANNING state.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   HUD.Destroy();
   Indicators.Release();
   
   // Auto-generate detailed performance reports on exit
   Reports.GeneratePerformanceReport("final_report.txt");
   
   Logger.Info("Deinitialization complete. Dashboard, indicator handles, and final reports clean.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Position-level active trade tracking (run on every tick for real-time SL modification)
   Trade.ManageActiveTrades(_Symbol);
   
   // 2. Bar-level signal generation (avoid intensive calculations inside every tick)
   if(IsNewBar())
   {
      // Refresh indicator datasets
      if(!Indicators.UpdateData())
      {
         Logger.Warning("Failed to update indicator buffers. Will retry on next tick.");
         // Reset last bar time to force retry on next tick
         m_last_bar_time = 0;
         return;
      }
      
      // Update market structure definitions
      SMC.ScanSMC();
      
      datetime now = TimeCurrent();
      
      // Filter Checklist
      string news_name = "";
      datetime news_time = 0;
      bool news_paused = InpUseNewsFilter && News.IsTradingPaused(now, InpNewsMinsBefore, InpNewsMinsAfter, news_name, news_time);
      bool session_active = Sessions.IsAnySessionActive(now);
      bool risk_ok = Risk.IsTradingAllowed(_Symbol);
      
      // Check entry conditions
      if(!news_paused && session_active && risk_ok)
      {
         // Verify maximum one-position constraint
         if(!Trade.IsPositionOpen(_Symbol))
         {
            double sl = 0.0, tp = 0.0;
            int signal = Signal.GenerateSignal(sl, tp);
            
            if(signal != 0)
            {
               double atr_val = Indicators.GetATR_Pri(1);
               double close_val = Indicators.GetClose_Pri(1);
               double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               double sl_dist_pts = MathAbs(close_val - sl) / point;
               
               double lot = Money.CalculateLotSize(_Symbol, sl_dist_pts, atr_val);
               
               if(lot > 0.0)
               {
                  string comment = StringFormat("PGAI_%s", (signal == 1) ? "BUY" : "SELL");
                  if(signal == 1)
                  {
                     Trade.OpenBuy(lot, sl, tp, comment);
                  }
                  else
                  {
                     Trade.OpenSell(lot, sl, tp, comment);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // CPU Optimization: HUD refreshes strictly on a 1-second interval, not on ticks
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit  = AccountInfoDouble(ACCOUNT_PROFIT);
   
   // Reconstruct day starting point
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day_start = StructToTime(dt);
   
   // Calculate day closed trades profit
   double closed_deals_profit = balance - AccountInfoDouble(ACCOUNT_BALANCE); // Fallback reference
   if(HistorySelect(day_start, TimeCurrent()))
   {
      closed_deals_profit = 0.0;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY) &&
               type != DEAL_TYPE_BALANCE)
            {
               closed_deals_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                                     HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                                     HistoryDealGetDouble(ticket, DEAL_SWAP);
            }
         }
      }
   }
   
   // Calculate Win Rate today dynamically
   double win_rate = 0.0;
   if(HistorySelect(day_start, TimeCurrent()))
   {
      int win_deals = 0;
      int total_deals = 0;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == (long)InpMagicNumber &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
            {
               long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
               long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
               if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY) &&
                  type != DEAL_TYPE_BALANCE)
               {
                  total_deals++;
                  double deal_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                                       HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                                       HistoryDealGetDouble(ticket, DEAL_SWAP);
                  if(deal_profit >= 0.0) win_deals++;
               }
            }
         }
      }
      if(total_deals > 0)
      {
         win_rate = ((double)win_deals / total_deals) * 100.0;
      }
   }
   
   double total_day_profit = closed_deals_profit + profit;
   
   double dd = 0.0;
   Risk.CheckDailyDrawdown(dd);
   
   // Calculate H1 Trend state
   string trend_str = "NEUTRAL";
   double ema20 = Indicators.GetEMA20_Trend(0);
   double ema50 = Indicators.GetEMA50_Trend(0);
   double ema200 = Indicators.GetEMA200_Trend(0);
   if(ema20 > ema50 && ema50 > ema200)      trend_str = "UPTREND";
   else if(ema20 < ema50 && ema50 < ema200) trend_str = "DOWNTREND";
   
   double atr = Indicators.GetATR_Pri(0) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double rsi = Indicators.GetRSI_Pri(0);
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   // Count magic trades
   int open_trades = 0;
   int total_pos = PositionsTotal();
   for(int i = 0; i < total_pos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
         {
            open_trades++;
         }
      }
   }
   
   int day_trades = Risk.GetTradesCountToday();
   bool active = false;
   string status_str = GetTradingStatusString(active);
   
   HUD.Update(balance, equity, total_day_profit, dd, trend_str, 
              Indicators.GetEMA20_Pri(0), Indicators.GetEMA50_Pri(0), Indicators.GetEMA200_Pri(0),
              atr, rsi, spread, open_trades, day_trades, win_rate, status_str);
}

//+------------------------------------------------------------------+
//| IsNewBar                                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t[1];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) > 0)
   {
      if(t[0] != m_last_bar_time)
      {
         m_last_bar_time = t[0];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetTradingStatusString                                           |
//+------------------------------------------------------------------+
string GetTradingStatusString(bool &out_is_active)
{
   datetime now = TimeCurrent();
   
   // Check if weekend
   if(CUtilities::IsWeekend(now))
   {
      out_is_active = false;
      return "PAUSED (WEEKEND)";
   }
   
   // Check News
   string news_name = "";
   datetime news_time = 0;
   if(InpUseNewsFilter && News.IsTradingPaused(now, InpNewsMinsBefore, InpNewsMinsAfter, news_name, news_time))
   {
      out_is_active = false;
      return "PAUSED (NEWS)";
   }
   
   // Check Session
   if(!Sessions.IsAnySessionActive(now))
   {
      out_is_active = false;
      return "PAUSED (SESSION)";
   }
   
   // Check Risk Limits
   double temp_dd = 0.0;
   if(!Risk.CheckDailyDrawdown(temp_dd) || !Risk.CheckWeeklyDrawdown(temp_dd) || !Risk.CheckMonthlyDrawdown(temp_dd))
   {
      out_is_active = false;
      return "BLOCKED (DRAWDOWN)";
   }
   
   if(Risk.GetTradesCountToday() >= InpMaxTradesPerDay)
   {
      out_is_active = false;
      return "BLOCKED (MAX TRADES)";
   }
   
   out_is_active = true;
   return "SCANNING";
}
