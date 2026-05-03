#!/usr/bin/env python3
"""
Script kiểm tra IP ESP32-CAM
Tự động scan và tìm ESP32 trên mạng
"""

import socket
import requests
import subprocess
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from colorama import init, Fore, Style

init(autoreset=True)

# IP hiện tại trong code
CURRENT_IP = "192.168.1.27"
ESP32_PORT = 81

def print_header(text):
    print(f"\n{Fore.CYAN}{'='*60}")
    print(f"{Fore.CYAN}{text:^60}")
    print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}")

def print_success(text):
    print(f"{Fore.GREEN}✅ {text}{Style.RESET_ALL}")

def print_error(text):
    print(f"{Fore.RED}❌ {text}{Style.RESET_ALL}")

def print_info(text):
    print(f"{Fore.BLUE}ℹ️  {text}{Style.RESET_ALL}")

def print_warning(text):
    print(f"{Fore.YELLOW}⚠️  {text}{Style.RESET_ALL}")

def get_local_ip():
    """Lấy IP máy tính hiện tại"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return None

def get_network_prefix(ip):
    """Lấy network prefix (192.168.1.x)"""
    parts = ip.split('.')
    return '.'.join(parts[:3])

def check_esp32(ip):
    """Kiểm tra xem IP có phải ESP32 không"""
    try:
        # Test /status endpoint
        url = f"http://{ip}:{ESP32_PORT}/status"
        response = requests.get(url, timeout=1)
        
        if response.status_code == 200:
            try:
                data = response.json()
                if 'ip' in data or 'status' in data:
                    return True, data
            except:
                pass
        
        # Test /stream endpoint
        url = f"http://{ip}:{ESP32_PORT}/stream"
        response = requests.get(url, timeout=1, stream=True)
        if response.status_code == 200:
            content_type = response.headers.get('Content-Type', '')
            if 'multipart' in content_type or 'image' in content_type:
                return True, {'ip': ip, 'type': 'stream'}
        
        return False, None
    except:
        return False, None

def scan_network(network_prefix):
    """Scan toàn bộ subnet để tìm ESP32"""
    print_info(f"Đang scan mạng {network_prefix}.0/24...")
    print_info("Quá trình này có thể mất 30-60 giây...")
    
    found_devices = []
    
    with ThreadPoolExecutor(max_workers=50) as executor:
        futures = {}
        for i in range(1, 255):
            ip = f"{network_prefix}.{i}"
            futures[executor.submit(check_esp32, ip)] = ip
        
        completed = 0
        for future in as_completed(futures):
            completed += 1
            if completed % 50 == 0:
                print(f"   Progress: {completed}/254", end='\r')
            
            ip = futures[future]
            try:
                is_esp32, data = future.result()
                if is_esp32:
                    found_devices.append((ip, data))
            except:
                pass
    
    print(" " * 50, end='\r')  # Clear progress line
    return found_devices

def main():
    print_header("🔍 KIỂM TRA IP ESP32-CAM")
    
    # 1. Hiển thị IP hiện tại trong code
    print_info(f"IP hiện tại trong code: {CURRENT_IP}")
    print()
    
    # 2. Test IP hiện tại
    print_header("TEST 1: KIỂM TRA IP HIỆN TẠI")
    print_info(f"Testing: http://{CURRENT_IP}:{ESP32_PORT}")
    
    is_current_ok, current_data = check_esp32(CURRENT_IP)
    
    if is_current_ok:
        print_success(f"ESP32 phản hồi tại IP hiện tại: {CURRENT_IP}")
        if current_data:
            print_info(f"  Data: {current_data}")
        print()
        print_success("✅ IP vẫn đúng - KHÔNG CẦN THAY ĐỔI")
        print()
        print_info("Bạn có thể chạy test hệ thống:")
        print_info("  python test_system.py")
        return
    else:
        print_error(f"ESP32 không phản hồi tại {CURRENT_IP}")
        print_warning("IP có thể đã thay đổi - cần scan mạng")
    
    # 3. Lấy IP máy tính
    print()
    print_header("TEST 2: SCAN MẠNG")
    
    local_ip = get_local_ip()
    if not local_ip:
        print_error("Không thể xác định IP máy tính")
        print_info("Vui lòng kiểm tra Serial Monitor để lấy IP ESP32")
        return
    
    print_success(f"IP máy tính: {local_ip}")
    network_prefix = get_network_prefix(local_ip)
    print_info(f"Network: {network_prefix}.0/24")
    print()
    
    # 4. Scan network
    found = scan_network(network_prefix)
    
    print()
    print_header("📊 KẾT QUẢ SCAN")
    
    if not found:
        print_error("Không tìm thấy ESP32-CAM trên mạng")
        print()
        print_info("Các bước kiểm tra:")
        print_info("  1. ESP32 có nguồn không?")
        print_info("  2. ESP32 đã kết nối WiFi chưa?")
        print_info("  3. Mở Serial Monitor (115200 baud) để xem log")
        print_info("  4. Reset ESP32 và tìm dòng: '✅ Connected! IP: ...'")
        return
    
    print_success(f"Tìm thấy {len(found)} ESP32 device(s):")
    print()
    
    for ip, data in found:
        print(f"{Fore.GREEN}  📹 ESP32-CAM: {ip}:{ESP32_PORT}{Style.RESET_ALL}")
        if data:
            for key, val in data.items():
                print(f"     {key}: {val}")
        print()
    
    # 5. Hướng dẫn cập nhật
    if len(found) == 1:
        new_ip = found[0][0]
        if new_ip != CURRENT_IP:
            print_header("📝 CẬP NHẬT IP MỚI")
            print_warning(f"IP đã thay đổi: {CURRENT_IP} → {new_ip}")
            print()
            print_info("Cần cập nhật IP tại 2 file:")
            print_info(f"  1. ESP32CAM/face_recognition_advanced.py (dòng 36)")
            print_info(f"     ESP32_IP = \"{new_ip}\"")
            print()
            print_info(f"  2. test_system.py (dòng 17)")
            print_info(f"     ESP32_IP = \"{new_ip}\"")
            print()
            
            # Tự động cập nhật?
            try:
                choice = input(f"{Fore.YELLOW}Tự động cập nhật IP? (y/n): {Style.RESET_ALL}").lower()
                if choice == 'y':
                    update_ip_in_files(new_ip)
            except KeyboardInterrupt:
                print("\n")
    else:
        print_warning(f"Tìm thấy {len(found)} ESP32 - vui lòng chọn đúng IP")

def update_ip_in_files(new_ip):
    """Tự động cập nhật IP trong các file"""
    files = [
        ('ESP32CAM/face_recognition_advanced.py', 'ESP32_IP   = "', '"'),
        ('test_system.py', 'ESP32_IP = "', '"'),
    ]
    
    updated = []
    
    for filepath, prefix, suffix in files:
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Tìm và thay thế
            pattern = re.compile(f'{re.escape(prefix)}[^"]+{re.escape(suffix)}')
            new_content = pattern.sub(f'{prefix}{new_ip}{suffix}', content)
            
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print_success(f"Updated: {filepath}")
                updated.append(filepath)
        except Exception as e:
            print_error(f"Failed to update {filepath}: {e}")
    
    if updated:
        print()
        print_success(f"✅ Đã cập nhật {len(updated)} file(s)")
        print_info("Bây giờ có thể chạy: python test_system.py")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Đã hủy{Style.RESET_ALL}")
    except Exception as e:
        print_error(f"Error: {e}")
