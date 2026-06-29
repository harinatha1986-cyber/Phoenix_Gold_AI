//+------------------------------------------------------------------+
//|                                                   MoneyManager.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Handles position sizing calculations: Fixed Lot, Dynamic Risk,   |
//| ATR-based risk, and broker lot size normalization limits.        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Enum for sizing modes                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_SIZING_MODE
{
   LOT_MODE_FIXED,         // Fixed Lot Size
   LOT_MODE_DYNAMIC_RISK,  // Dynamic Risk % of Balance
   LOT_MODE_ATR_RISK       // ATR-Based Stop Risk %
};

//+------------------------------------------------------------------+
//| Class CMoneyManager                                              |
//| Calculates optimal trade volumes based on risk settings           |
//+------------------------------------------------------------------+
class CMoneyManager
{
private:
   ENUM_LOT_SIZING_MODE m_sizing_mode;      // Sizing mode (Fixed, Dynamic, ATR)
   double               m_fixed_lot_val;    // Lot size for fixed mode (e.g. 0.1)
   double               m_risk_percent;     // Risk percent per trade (e.g. 1.0%)
   double               m_atr_multiplier;   // ATR stop loss multiplier (e.g. 2.0)

public:
                        CMoneyManager();
                       ~CMoneyManager() {}
                       
   // Configuration setters
   void                 SetSizingMode(const ENUM_LOT_SIZING_MODE mode, const double fixed_lot, 
                                      const double risk_pct, const double atr_mult);

   // Calculate lot size
   double               CalculateLotSize(const string symbol, const double stop_loss_points, const double atr_value);
   
   // Normalize lot size according to broker specs
   double               NormalizeVolume(const string symbol, const double raw_lot);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMoneyManager::CMoneyManager() : m_sizing_mode(LOT_MODE_DYNAMIC_RISK),
                                 m_fixed_lot_val(0.1),
                                 m_risk_percent(1.0),
                                 m_atr_multiplier(2.0)
{
}

//+------------------------------------------------------------------+
//| SetSizingMode                                                    |
//+------------------------------------------------------------------+
void CMoneyManager::SetSizingMode(const ENUM_LOT_SIZING_MODE mode, const double fixed_lot, 
                                  const double risk_pct, const double atr_mult)
{
   m_sizing_mode = mode;
   m_fixed_lot_val = fixed_lot;
   m_risk_percent = risk_pct;
   m_atr_multiplier = atr_mult;
   
   string mode_str = (mode == LOT_MODE_FIXED) ? "Fixed Lot" : 
                     (mode == LOT_MODE_DYNAMIC_RISK) ? "Dynamic Risk" : "ATR-Based Risk";
                     
   Logger.Info(StringFormat("Money Manager mode set to: %s. FixedLot=%.2f, Risk%%=%.2f%%, ATR_Mult=%.2f",
      mode_str, m_fixed_lot_val, m_risk_percent, m_atr_multiplier));
}

//+------------------------------------------------------------------+
//| CalculateLotSize                                                 |
//+------------------------------------------------------------------+
double CMoneyManager::CalculateLotSize(const string symbol, const double stop_loss_points, const double atr_value)
{
   // 1. Fixed Lot Mode
   if(m_sizing_mode == LOT_MODE_FIXED)
   {
      return NormalizeVolume(symbol, m_fixed_lot_val);
   }
   
   double account_val = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_val * (m_risk_percent / 100.0);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_val = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(point <= 0.0 || tick_size <= 0.0 || tick_val <= 0.0)
   {
      Logger.Error("Broker symbol values invalid. Cannot calculate risk-based lot sizing.");
      return NormalizeVolume(symbol, m_fixed_lot_val);
   }
   
   // Value of 1 point of movement for 1 contract lot in deposit currency
   double point_val = (tick_val / tick_size) * point;
   
   double sl_points = stop_loss_points;
   
   // 2. ATR-Based Risk Mode
   if(m_sizing_mode == LOT_MODE_ATR_RISK)
   {
      if(atr_value <= 0.0)
      {
         Logger.Warning("Invalid ATR value provided. Falling back to default fixed SL points.");
         sl_points = stop_loss_points;
      }
      else
      {
         sl_points = (atr_value * m_atr_multiplier) / point;
      }
   }
   
   // Ensure Stop Loss is valid to prevent division by zero
   if(sl_points <= 0.0)
   {
      Logger.Warning("Stop Loss points <= 0. Cannot compute risk lot size. Using broker minimum lot.");
      return NormalizeVolume(symbol, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
   }
   
   double raw_lot = risk_amount / (sl_points * point_val);
   double final_lot = NormalizeVolume(symbol, raw_lot);
   
   // Log the lot sizing decision details
   Logger.Info(StringFormat("Lot Sizing - Balance: %.2f | Risk Amt: %.2f | SL Points: %.1f | Calc Lot: %.2f | Final Lot: %.2f",
      account_val, risk_amount, sl_points, raw_lot, final_lot));
      
   return final_lot;
}

//+------------------------------------------------------------------+
//| NormalizeVolume                                                  |
//+------------------------------------------------------------------+
double CMoneyManager::NormalizeVolume(const string symbol, const double raw_lot)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if(volume_step <= 0.0) volume_step = 0.01;
   if(min_lot <= 0.0) min_lot = 0.01;
   if(max_lot <= 0.0) max_lot = 100.0;
   
   // Round down to the nearest volume step
   double normalized_lot = MathFloor(raw_lot / volume_step) * volume_step;
   
   // Keep in broker limits
   if(normalized_lot < min_lot)
   {
      // If the calculated lot is extremely small, return min lot to allow execution,
      // or return 0.0 to prevent over-risking. Let's return 0.0 if it is less than half of min lot.
      if(normalized_lot < min_lot * 0.5)
      {
         return 0.0;
      }
      return min_lot;
   }
   if(normalized_lot > max_lot)
   {
      return max_lot;
   }
   
   // Format to broker decimals (based on volume step)
   int decimals = 0;
   double step = volume_step;
   while(step < 1.0)
   {
      step *= 10.0;
      decimals++;
   }
   
   return NormalizeDouble(normalized_lot, decimals);
}
