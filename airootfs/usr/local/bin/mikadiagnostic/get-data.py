import os
import psutil
import subprocess
import statistics
import time
import cpuinfo
import platform
import GPUtil
import datetime
import matplotlib.pyplot as plt


#---------------------------------------------------------#
#                                                         #
# ------------------ CONSOLE OUTPUT COLORS ---------------#
#                                                         #
#---------------------------------------------------------#
def prError(skk):print("\033[91m{}\033[00m" .format(skk))
def prOk(skk):print("\033[92m{}\033[00m" .format(skk))
def prWarning(skk):print("\033[93m{}\033[00m" .format(skk))
def prInfo(skk):print("\033[94m{}\033[00m" .format(skk))

version = "12.09.23 BETA"

user_home = os.path.expanduser("~")
subdirectory = "Documents"

#---------------------------------------------------------#
#                                                         #                            
# ------------------ GENERAL SYSTEM INFO -----------------#
#                                                         #
#---------------------------------------------------------#

def getSystemSpecs():
    specs = {}
    prInfo("[INFO] - Retrieving system specifications")

    # Retrieve RAM information
    ram = psutil.virtual_memory()
    total_ram = ram.total // (1024 * 1024)
    specs["Total RAM"] = total_ram

    # Retrieve CPU information
    cpu_info = cpuinfo.get_cpu_info()
    cpu_name = cpu_info["brand_raw"]
    cpu_architecture = platform.machine()
    cpu_cores = psutil.cpu_count(logical=False)
    cpu_threads = psutil.cpu_count(logical=True)
    cpu_max_freq = psutil.cpu_freq().max
    cpu_base_freq = psutil.cpu_freq().min
    specs["CPU"] = cpu_name
    specs["CPU Architecture"] = cpu_architecture
    specs["CPU Cores"] = cpu_cores
    specs["CPU Threads"] = cpu_threads
    specs["Max CPU Frequency"] = cpu_max_freq
    specs["Base CPU Frequency"] = cpu_base_freq

    network_cards = psutil.net_if_addrs()
    network_card_list = []
    for interface_name, interface_addresses in network_cards.items():
        for address in interface_addresses:
            if str(address.family) == 'AddressFamily.AF_INET':
                network_card_list.append(interface_name)
    specs["Network Cards"] = network_card_list

    try:
        gpus = GPUtil.getGPUs()
        gpu_list = [gpu.name for gpu in gpus]
        specs["GPU Names"] = gpu_list
    except Exception as e:
        specs["GPU Names"] = ["Error retrieving GPU info: " + str(e)]

    prOk("[OK] - System specifications retrieved")

    return specs

def get_system_info():
    system_info = {}

    # Kernel version (Linux)
    kernel_version = get_linux_kernel_version()
    system_info['Kernel Version'] = kernel_version

    uptime = get_system_uptime()
    system_info['Uptime'] = uptime

    domain_name = get_domain_name()
    system_info['Domain Name'] = domain_name

    hostname = get_hostname()
    system_info['Hostname'] = hostname

    boot_mode = get_boot_mode()
    system_info['Boot Mode'] = boot_mode

    boot_state = get_boot_state()
    system_info['Boot State'] = boot_state

    return system_info

# Kernel version (Linux)
def get_linux_kernel_version():
    return platform.uname().release

def get_system_uptime():
    uptime_output = subprocess.check_output(['uptime', '-p'], universal_newlines=True)
    return uptime_output.strip()

def get_domain_name():
    return platform.node().split('.', 1)[-1] 

def get_hostname():
    return platform.node()

def get_boot_mode_linux():
    boot_mode_output = subprocess.check_output(['lsblk', '-o', 'NAME,FSTYPE,MOUNTPOINT', '-J'], universal_newlines=True)
    if 'boot/efi' in boot_mode_output:
        return 'UEFI'
    return 'Legacy BIOS'

def get_boot_mode():
    if platform.system() == 'Linux':
        return get_boot_mode_linux()
    return None


def get_boot_state():
    # FIXME
    return 'N/A'



def get_battery_status():
    battery = psutil.sensors_battery()
    prInfo("[INFO] - Retrieving battery status")
    if battery is not None:
        percent = 0
        power_status = "Unknown"
        time_remaining = 0
        plugged = battery.power_plugged
        percent = battery.percent
        remaining = battery.secsleft
        power_status = "Plugged in" if plugged else "Not plugged in"
        
        if plugged:
            time_remaining = "Charging"
        else:
            hours = remaining // 3600
            minutes = (remaining % 3600) // 60
            time_remaining = f"{hours} hours {minutes} minutes"
        
        prOk("[OK] - Battery status retrieved")
        return {
            'percentage': percent,
            'power_status': power_status,
            'time_remaining': time_remaining,
        }
    else:
        prError("[ERROR] - No battery information available.")
        return None



def get_running_processes():
    processes = []
    for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
        processes.append({
            'pid': proc.pid,
            'name': proc.name(),
            'cpu_percent': proc.cpu_percent(),
            'memory_percent': proc.memory_percent()
        })
    # Sort processes by CPU percent in descending order
    processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
    return processes


#---------------------------------------------------------#
#                                                         #                            
# ------------------- GENERATING REPORT ------------------#
#                                                         #
#---------------------------------------------------------#

def generate_line_graph(temperatures, filename):
    x = list(range(1, len(temperatures) + 1))
    y = temperatures

    plt.rcParams['axes.facecolor'] = '#222222'  
    plt.rcParams['axes.edgecolor'] = '#222222'  
    plt.rcParams['axes.labelcolor'] = '#ccc' 
    plt.rcParams['xtick.color'] = '#ccc'
    plt.rcParams['ytick.color'] = '#ccc'

    fig, ax = plt.subplots()

    ax.set_facecolor('#222222')
    plt.tight_layout()
    ax.plot(x, y, color='#FF0800')  

    ax.set_xlabel('Time (seconds)')
    ax.set_ylabel('CPU Temperature (°C)')
    ax.set_title('CPU Temperature drop-off after benchmark')

    
    ax.grid(True, color='#ffffff', linestyle='--')  

    file_path = os.path.join(user_home, subdirectory)

    plt.savefig(f"{file_path}/{filename}_cpu_temperature_graph.png", bbox_inches='tight')
    plt.close()

    print('Line graph generated: ', f"{filename}_cpu_temperature_graph.png")


def createProcessesTable():
    running_processes = get_running_processes()
    total_processes = len(running_processes)
    totalMemoryPercent = 0
    for process in running_processes:
        totalMemoryPercent += process['memory_percent']
    
    totalCPUPercent = 0
    for process in running_processes:
        totalCPUPercent += process['cpu_percent']

    table_rows = ''
    for process in running_processes:
        table_rows += f"""
        <tr>
            <td>{process['pid']}</td>
            <td>{process['name']}</td>
            <td>{process['cpu_percent']}</td>
            <td>{process['memory_percent']}</td>
        </tr>"""

    html = f"""
<div class="container">
    <h1 id="systemproc">Running system processes</h1>
    <p>Total processes: {total_processes}</p>
    <p>Total CPU percent: {totalCPUPercent}% <span style="color:red"><b>BROKEN</b></span></p>
    <p>Total memory percent: {totalMemoryPercent}%</p>
    <table>
        <tr>
            <th>PID</th>
            <th>Process name</th>
            <th>CPU percent</th>
            <th>Memory percent</th>
        </tr>
        {table_rows}
    </table>
</div>
    """
    return html


def getPossibleWarnings(mintemp, maxtemp, avgtemp, interval, idletemp, dropOff):
    running_processes = get_running_processes()
    totalMemoryPercent = 0
    for process in running_processes:
        totalMemoryPercent += process['memory_percent']
    allIssues = []

    warningStatus = False

    if maxtemp is not None:
        if maxtemp > 80:
            allIssues.append(f"<p><span style='color:orange'>[WARNING]</span> - Maximum CPU temperature during benchmark is high ({maxtemp}°C).</p>")
            warningStatus = True
    if avgtemp is not None:
        if avgtemp > 70:
            allIssues.append(f"<p><span style='color:orange'>[WARNING]</span> - Average CPU temperature during benchmark is high ({avgtemp}°C).</p>")
            warningStatus = True
    if idletemp is not None:
        if idletemp > 55:
            allIssues.append(f"<p><span style='color:orange'>[WARNING]</span> - CPU idle temperature is high ({idletemp}°C).</p>")
            warningStatus = True
    
    if warningStatus == True:
        allIssues.append(f"<p>1. This could potentially be a cooling problem, try checking your termal paste if it hasn't been renewed in a while. Or maybe even replacing the CPU cooler all together. If the Idle temp is high you can also check your current running background processes.</p>") 

    returnInfo = ""
    for issue in allIssues:
        returnInfo += issue

    return returnInfo


def getPossibleInfo(mintemp, maxtemp, avgtemp, interval, idletemp, dropOff):
    running_processes = get_running_processes()
    totalMemoryPercent = 0
    for process in running_processes:
        totalMemoryPercent += process['memory_percent']
    allIssues = []

    ram = psutil.virtual_memory()
    total_ram = ram.total // (1024 * 1024 * 1024)
    print(total_ram)
    
    # Declaring variables
    memoryInfo = False
    lowDurationInfo = False
    lowCpuTempInfo = False

    if idletemp is not None:
        if idletemp < 30:
            allIssues.append(f"<p><span style='color:#0096FF'>[INFO]</span> - Minimum CPU temperature is low ({mintemp}°C).</p>")
            lowCpuTempInfo = True
    if interval is not None:
        if interval < 60:
            allIssues.append(f"<p><span style='color:#0096FF'>[INFO]</span> - Benchmark duration is low ({interval} seconds).</p>")
            lowDurationInfo = True
    if totalMemoryPercent is not None:
        if totalMemoryPercent > 70:
            if total_ram < 17:
                allIssues.append(f"<p><span style='color:#0096FF'>[INFO]</span> - Total memory usage is high ({totalMemoryPercent}%).</p>")
                memoryInfo = True

    if lowCpuTempInfo == True:
        allIssues.append(f"<p>1. You have a low CPU idle temparature, this doesn't have to be dangarous just make sure to prevent condensation. Condensation occurs when the temp of the components than the air surrounding it.</p>")
    if lowDurationInfo == True:
        allIssues.append(f"<p>2. Your benchmark duration is low, this could make the result of the benchmark invalid.</p>")
    if memoryInfo == True:
        allIssues.append(f"<p>3. Memory usage is high, do you have many tabs open on the background?</p>")

    returnInfo = ""
    for issue in allIssues:
        returnInfo += issue
    
    return returnInfo


def printResults(min_temperature, max_temperature, avg_temperature, interval, idle_temperature, dropOff):
    systemInfo = get_system_info()
    processesTable = createProcessesTable()
    batteryStatus = get_battery_status()
    systemSpecs = getSystemSpecs()
    possible_warnings =  getPossibleWarnings(min_temperature, max_temperature, avg_temperature, interval, idle_temperature, dropOff)
    possible_info = getPossibleInfo(min_temperature, max_temperature, avg_temperature, interval, idle_temperature, dropOff)

    # Default values for variables to prevent errors 
    if idle_temperature is None: idle_temperature = "N/A"
    if max_temperature is None: max_temperature = "N/A"
    if avg_temperature is None: avg_temperature = "N/A"
    if min_temperature is None: min_temperature = "N/A"
    if interval is None: interval = "N/A"
    if dropOff is None: dropOff = "N/A"

    if batteryStatus is not None:
        battery_percentage = batteryStatus['percentage']
        power_status = batteryStatus['power_status']
        time_remaining = batteryStatus['time_remaining']
    else:
        battery_percentage = "N/A"
        power_status = "N/A"
        time_remaining = "N/A"
        print("Battery information not available.")


    prInfo("[INFO] - Generating HTML report")
    # now = datetime.now()
    now = datetime.datetime.now()
    time = now.strftime("%Y-%m-%d-%H:%M:%S")
    generate_line_graph(dropOff, time)
    
    template = f"""
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Report from - {time}</title>
    <style>
        body {{
            background-color: #222;
            color: #fff;
            font-family: Arial, sans-serif;
        }}

        h1 {{
            color: #fff;
        }}

        p {{
            color: #ccc;
        }}

        ul {{
            list-style-type: none;
            background-color: #333;
            padding: 10px;
            margin: 0;
            display: flex;
            justify-content: space-around;
        }}

        li {{
            display: inline-block;
            margin-right: 20px;
        }}

        a {{
            color: #fff;
            text-decoration: none;
        }}

        .container {{
            margin: 20px;
        }}

        table {{
            border-collapse: collapse;
            width: 100%;
            margin-top: 20px;
        }}

        th, td {{
            padding: 8px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}

        th {{
            background-color: #333;
            color: #fff;
        }}

        .dark-mode {{
            background-color: #222;
            color: #fff;
        }}
    </style>
</head>

<body class="dark-mode">
    <ul>
        <li><a href="#systemspec">System specifications</a></li>
        <li><a href="#sysinfo">System info</a></li>
        <li><a href="#battery">Battery status</a></li>
        <li><a href="#benchmark">CPU benchmark results</a></li>
        <li><a href="#systemproc">Running system processes</a></li>
    </ul>
    <div class="container">
        <h1>Possible problems (BETA)</h1>
        <p><b>Some of the information retrieved by this program might be incorrect. This is because the program is still in BETA. If you find any problems, please open an issue on the github repo.</b></p>
        {possible_warnings}
        {possible_info}
    <hr>
    <div class="container">
        <p>Report generated on {time}</p>
        <p>System benchmark version: {version}</p>
    </div>
    <div class="container">
        <h1 id="systemspec">System specifications</h1>
        <p>CPU idle temp: {idle_temperature}<br>CPU: {systemSpecs['CPU']} <br>CPU Architecture: {systemSpecs['CPU Architecture']} <br>CPU Cores: {systemSpecs['CPU Cores']} <br>CPU Threads: {systemSpecs['CPU Threads']} <br>Max CPU Frequency: {systemSpecs['Max CPU Frequency']}mhz<br>Base CPU Frequency: {systemSpecs['Base CPU Frequency']}mhz<br>GPU Names: {systemSpecs['GPU Names']} <br>Network Cards: {systemSpecs['Network Cards']} <br>Total RAM: {systemSpecs['Total RAM']}MB </p>
    </div>
    <hr>
    <div class="container">
        <h1 id="sysinfo">System info</h1>
        <p>Kernel/linux version: {systemInfo['Kernel Version']}<br>Uptime: {systemInfo['Uptime']}<br>Hostname: {systemInfo['Hostname']}<br>Domainname: {systemInfo['Domain Name']}<br>Boot mode: {systemInfo['Boot Mode']}<br>Boot state: {systemInfo['Boot State']}</p>
    </div>
    <hr>
    <div class="container">
        <h1 id="battery">Battery status</h1>
        <p>Percentage: {battery_percentage}% <br>Power status: {power_status} <br>Time remaining: {time_remaining} </p>
    </div>
    <hr>
    <div class="container">
        <h1 id="benchmark">Benchmark results</h1>
        <p>Benchmark duration: {interval}sec <br>Maximum CPU temperature: {max_temperature}°C <br>Average CPU temperature: {avg_temperature}°C <br>Minimum CPU temperature: {min_temperature}°C </p>
        <img src="{time}_cpu_temperature_graph.png" alt="CPU Temperature Graph">
    </div>
    <hr>
    {processesTable}
</body>

</html>
"""

    # write = open(time + ".html", "w")
    # write.write(template)
    # write.close()
    # prOk(f"[OK] - HTML report generated: {time}.html")
    
    file_path = os.path.join(user_home, subdirectory, f"{time}.html")

    with open(file_path, "w") as write:
        write.write(template)

    prOk(f"[OK] - HTML report generated: {file_path}")



#---------------------------------------------------------#
#                                                         #                            
# ------------------- SYSTEM BENCHMARK -------------------#
#                                                         #
#---------------------------------------------------------#

def cpuTempDropOff():
    temperatures = []
    start_time = time.time()

    while time.time() - start_time < 60:
        temperature = get_cpu_temperature()
        if temperature is not None:
            temperatures.append(temperature)
        time.sleep(1)

    return temperatures


def get_cpu_temperature():
    try:
        prInfo("[INFO] - Retrieving CPU temperature")
        thermal_dir = '/sys/class/thermal'
        for device in os.listdir(thermal_dir):
            if device.startswith('thermal_zone'):
                temp_file = os.path.join(thermal_dir, device, 'temp')
                with open(temp_file, 'r') as f:
                    temperature = float(f.read().strip()) / 1000.0
                    prOk(f"[OK] - CPU temperature: {temperature}°C")
                    return temperature
    except Exception as e:
        prError(f"[ERROR] - getting CPU temperature: {e}")

    return None


def monitor_cpu_temperature(interval, utilization):
    idle_temperature = get_cpu_temperature()
    temperatures = []
    start_time = time.time()
    prInfo(f"[INFO] - Starting benchmark for {interval} seconds and CPU utilization of {utilization}%")

    while time.time() - start_time < interval:
        temperature = get_cpu_temperature()
        if temperature is not None:
            temperatures.append(temperature)
        time.sleep(1)

    if temperatures:
        min_temperature = min(temperatures)
        max_temperature = max(temperatures)
        avg_temperature = statistics.mean(temperatures)

        prOk(f"[OK] - CPU test finished.")
        prWarning("[WARNING] - Waiting 60 seconds for the CPU to cool down, and other processes to finish.")
        dropOff = cpuTempDropOff()
        printResults(min_temperature, max_temperature, avg_temperature, interval, idle_temperature, dropOff)
    else:
        print("No temperature data available.")


if __name__ == '__main__':
    interval = 0
    utilization = 0 
    userinput = input("Would you like to customize the benchmark? [y/n] ")
    if userinput == "n":
        prInfo("[INFO] - Using default values...")
        interval = 120
        utilization = 100
    else:
        interval = int(input("Enter the benchmark duration in seconds: "))
        utilization = int(input("Enter the CPU utilization in percentage: "))

    prWarning(f"[WARNING] - For the best results, please stay focussed on this window during the test. The program will start in 5 seconds.")
    time.sleep(5)
    cpu_load_script_path = '/usr/local/bin/mikadiagnostic/assets/loads/cpu-load.py' 

    cpu_load_process = subprocess.Popen(['python', cpu_load_script_path, str(interval), str(utilization)])
    monitor_cpu_temperature(interval, utilization)
    cpu_load_process.terminate()