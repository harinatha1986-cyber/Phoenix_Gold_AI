//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Confluence engine blending Technical Indicators (EMAs, RSI, ATR) |
//| with Smart Money Concepts (BOS, CHoCH, OBs, Liquidity Sweeps).   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"
#include "IndicatorManager.mqh"
#include "SmartMoney.mqh"

//+------------------------------------------------------------------+
//| Signal Mode Enum                                                 |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   SIGNAL_MODE_INDICATORS_ONLY,  // Technical Indicators (EMAs, RSI)
   SIGNAL_MODE_SMC_ONLY,         // Smart Money Concepts (OB, Sweeps, BOS)
   SIGNAL_MODE_INSTITUTIONAL     // Confluence Blend (Indicators + SMC)
};

//+------------------------------------------------------------------+
//| Class CSignalEngine                                              |
//| Combines data structures and generates trade signals             |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   ENUM_SIGNAL_MODE     m_mode;
   double               m_min_rsi_buy;
   double               m_max_rsi_sell;
   double               m_min_atr_val;
   bool                 m_use_h1_confirm;
   bool                 m_use_smc_zones;
   
   CIndicatorManager   *m_indicators;
   CSmartMoney         *m_smc;

public:
                        CSignalEngine();
                       ~CSignalEngine() {}
                       
   // Link indicator and SMC managers
   void                 Init(CIndicatorManager *indicators, CSmartMoney *smc);
   
   // Configure signal parameters
   void                 Configure(const ENUM_SIGNAL_MODE mode, const double min_rsi_buy, const double max_rsi_sell,
                                  const double min_atr, const bool use_h1, const bool use_smc_zones);
                                  
   // Process inputs and check for triggers (Returns: 1 = BUY, -1 = SELL, 0 = No Signal)
   int                  GenerateSignal(double &out_sl, double &out_tp);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSignalEngine::CSignalEngine() : m_mode(SIGNAL_MODE_INSTITUTIONAL),
                                 m_min_rsi_buy(55.0),
                                 m_max_rsi_sell(45.0),
                                 m_min_atr_val(0.0),
                                 m_use_h1_confirm(true),
                                 m_use_smc_zones(true),
                                 m_indicators(NULL),
                                 m_smc(NULL)
{
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CSignalEngine::Init(CIndicatorManager *indicators, CSmartMoney *smc)
{
   m_indicators = indicators;
   m_smc = smc;
   Logger.Info("Signal Engine linked to Indicator Manager and Smart Money Module.");
}

//+------------------------------------------------------------------+
//| Configure                                                        |
//+------------------------------------------------------------------+
void CSignalEngine::Configure(const ENUM_SIGNAL_MODE mode, const double min_rsi_buy, const double max_rsi_sell,
                              const double min_atr, const bool use_h1, const bool use_smc_zones)
{
   m_mode = mode;
   m_min_rsi_buy = min_rsi_buy;
   m_max_rsi_sell = max_rsi_sell;
   m_min_atr_val = min_atr;
   m_use_h1_confirm = use_h1;
   m_use_smc_zones = use_smc_zones;
   
   string mode_str = (m_mode == SIGNAL_MODE_INDICATORS_ONLY) ? "Indicators Only" :
                     (m_mode == SIGNAL_MODE_SMC_ONLY) ? "SMC Only" : "Institutional Confluence";
                     
   Logger.Info(StringFormat("Signal Engine Configured: Mode=%s, RSI Buy/Sell %.1f/%.1f, MinATR=%.1f points, H1Confirm=%d, SMCZones=%d",
      mode_str, m_min_rsi_buy, m_max_rsi_sell, m_min_atr_val, m_use_h1_confirm, m_use_smc_zones));
}

//+------------------------------------------------------------------+
//| GenerateSignal                                                   |
//+------------------------------------------------------------------+
int CSignalEngine::GenerateSignal(double &out_sl, double &out_tp)
{
   if(m_indicators == NULL || m_smc == NULL)
   {
      Logger.Error("Signal Engine cannot run: Indicators or SMC references are NULL.");
      return 0;
   }
   
   string symbol = Symbol();
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double close = m_indicators.GetClose_Pri(1);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // 1. Technical Indicators Check
   double ema20 = m_indicators.GetEMA20_Pri(1);
   double ema50 = m_indicators.GetEMA50_Pri(1);
   double ema200 = m_indicators.GetEMA200_Pri(1);
   double rsi = m_indicators.GetRSI_Pri(1);
   double atr = m_indicators.GetATR_Pri(1);
   
   // ATR Volatility filter (check if volatility exists)
   if(atr < m_min_atr_val * point)
   {
      return 0; // Market too flat
   }
   
   // H1 Trend confirmation
   bool h1_bullish = true;
   bool h1_bearish = true;
   
   if(m_use_h1_confirm)
   {
      double ema20_h1 = m_indicators.GetEMA20_Trend(1);
      double ema50_h1 = m_indicators.GetEMA50_Trend(1);
      double ema200_h1 = m_indicators.GetEMA200_Trend(1);
      
      h1_bullish = (ema20_h1 > ema50_h1) && (ema50_h1 > ema200_h1);
      h1_bearish = (ema20_h1 < ema50_h1) && (ema50_h1 < ema200_h1);
   }
   
   // BUY rules: EMA20 > EMA50 > EMA200, RSI > 55, Price > EMA20, and H1 Trend Bullish
   bool ind_buy = (ema20 > ema50) && (ema50 > ema200) && (rsi > m_min_rsi_buy) && (close > ema20) && h1_bullish;
   
   // SELL rules: EMA20 < EMA50 < EMA200, RSI < 45, Price < EMA20, and H1 Trend Bearish
   bool ind_sell = (ema20 < ema50) && (ema50 < ema200) && (rsi < m_max_rsi_sell) && (close < ema20) && h1_bearish;
   
   // 2. Smart Money Concepts Check
   bool smc_buy = false;
   bool smc_sell = false;
   
   int pd_zone = m_smc.GetPremiumDiscountZone(close);
   
   double ob_top = 0.0, ob_bottom = 0.0;
   bool in_bull_ob = m_smc.IsPriceInOrderBlock(close, true, ob_top, ob_bottom);
   bool in_bear_ob = m_smc.IsPriceInOrderBlock(close, false, ob_top, ob_bottom);
   
   bool is_bull_sweep = false;
   bool has_sweep = m_smc.DetectLiquiditySweep(is_bull_sweep);
   bool bull_sweep_active = (has_sweep && is_bull_sweep);
   bool bear_sweep_active = (has_sweep && !is_bull_sweep);
   
   bool smc_bull_structure = m_smc.IsBOS() || m_smc.IsCHoCH();
   bool smc_bear_structure = m_smc.IsBOS() || m_smc.IsCHoCH();
   
   // Premium / Discount Zone filtration
   bool is_in_discount = (!m_use_smc_zones || pd_zone == -1);
   bool is_in_premium  = (!m_use_smc_zones || pd_zone == 1);
   
   // Bullish SMC confluence: Discount Zone AND (testing Bullish OB OR Bullish Liquidity Sweep OR Reversal structure BOS/CHoCH)
   smc_buy = is_in_discount && (in_bull_ob || bull_sweep_active || smc_bull_structure);
   
   // Bearish SMC confluence: Premium Zone AND (testing Bearish OB OR Bearish Liquidity Sweep OR Reversal structure BOS/CHoCH)
   smc_sell = is_in_premium && (in_bear_ob || bear_sweep_active || smc_bear_structure);
   
   // 3. Confluence Evaluation
   bool final_buy = false;
   bool final_sell = false;
   
   if(m_mode == SIGNAL_MODE_INDICATORS_ONLY)
   {
      final_buy = ind_buy;
      final_sell = ind_sell;
   }
   else if(m_mode == SIGNAL_MODE_SMC_ONLY)
   {
      final_buy = smc_buy;
      final_sell = smc_sell;
   }
   else if(m_mode == SIGNAL_MODE_INSTITUTIONAL)
   {
      final_buy = ind_buy && smc_buy;
      final_sell = ind_sell && smc_sell;
   }
   
   // 4. Calculate execution boundaries (Stop Loss and Take Profit)
   if(final_buy)
   {
      double entry = ask;
      double sl_price = m_smc.GetLastSwingLow();
      
      // Safety checks for SL placement
      if(sl_price <= 0.0 || sl_price >= entry || (entry - sl_price) < (50.0 * point))
      {
         // Fallback to ATR-based SL
         sl_price = entry - (2.0 * atr);
      }
      
      // Add a buffer below structural swing low
      sl_price -= (10.0 * point);
      sl_price = CUtilities::NormalizePrice(symbol, sl_price);
      
      double risk = entry - sl_price;
      if(risk <= 0.0) return 0;
      
      // Take Profit: Minimum Risk Reward of 1:2
      double tp_price = entry + (risk * 2.0);
      tp_price = CUtilities::NormalizePrice(symbol, tp_price);
      
      out_sl = sl_price;
      out_tp = tp_price;
      
      Logger.Info(StringFormat("BUY SIGNAL GENERATED: Entry %.2f | SL %.2f | TP %.2f | Risk %.2f points",
         entry, out_sl, out_tp, risk / point));
      return 1;
   }
   
   if(final_sell)
   {
      double entry = bid;
      double sl_price = m_smc.GetLastSwingHigh();
      
      // Safety checks for SL placement
      if(sl_price <= 0.0 || sl_price <= entry || (sl_price - entry) < (50.0 * point))
      {
         // Fallback to ATR-based SL
         sl_price = entry + (2.0 * atr);
      }
      
      // Add a buffer above structural swing high
      sl_price += (10.0 * point);
      sl_price = CUtilities::NormalizePrice(symbol, sl_price);
      
      double risk = sl_price - entry;
      if(risk <= 0.0) return 0;
      
      // Take Profit: Minimum Risk Reward of 1:2
      double tp_price = entry - (risk * 2.0);
      tp_price = CUtilities::NormalizePrice(symbol, tp_price);
      
      out_sl = sl_price;
      out_tp = tp_price;
      
      Logger.Info(StringFormat("SELL SIGNAL GENERATED: Entry %.2f | SL %.2f | TP %.2f | Risk %.2f points",
         entry, out_sl, out_tp, risk / point));
      return -1;
   }
   
   return 0; // No trade signal
}
