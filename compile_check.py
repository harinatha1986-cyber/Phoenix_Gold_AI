import os
import subprocess
import time

def find_metaeditor():
    paths = [
        r"C:\Program Files\XM Global MT5\MetaEditor64.exe",
        r"C:\Program Files\MetaTrader 5 IC Markets Global\MetaEditor64.exe",
        r"C:\Program Files\MetaTrader 5\MetaEditor64.exe"
    ]
    for p in paths:
        if os.path.exists(p):
            return p
    return None

def main():
    me = find_metaeditor()
    if not me:
        print("[ERROR] MetaEditor64.exe not found in standard paths.")
        return

    print(f"Using MetaEditor: {me}")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    mq5_path = os.path.join(script_dir, "Phoenix Gold AI.mq5")
    log_path = os.path.join(script_dir, "Phoenix Gold AI.log")
    ex5_path = os.path.join(script_dir, "Phoenix Gold AI.ex5")
    
    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(ex5_path):
        os.remove(ex5_path)
        
    print(f"Compiling: {mq5_path}")
    
    # MetaEditor compilation command line syntax:
    # MetaEditor64.exe /compile:"path_to_file" /log:"path_to_log"
    # Or just /compile:"path_to_file" /log (which writes to file.log)
    cmd = f'"{me}" /compile:"{mq5_path}" /log'
    print(f"Command: {cmd}")
    
    p = subprocess.Popen(cmd, shell=True)
    p.wait()
    
    # Wait for file output to settle
    time.sleep(2)
    
    if os.path.exists(ex5_path):
        print("\n[SUCCESS] Compilation Succeeded!")
        print(f"Generated EX5: {ex5_path}")
    else:
        print("\n[FAILED] Compilation Failed!")
        
    if os.path.exists(log_path):
        print("\n--- Compilation Log ---")
        try:
            with open(log_path, "r", encoding="utf-16") as f:
                print(f.read())
        except Exception:
            try:
                with open(log_path, "r", encoding="utf-8") as f:
                    print(f.read())
            except Exception as e:
                print(f"Could not read log: {e}")
    else:
        print("\nNo log file was generated. Check if MetaEditor was blocked or paths are correct.")

if __name__ == "__main__":
    main()
