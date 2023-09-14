import sys 
import multiprocessing
from cpu_load_generator import load_single_core, load_all_cores, from_profile


def generate_cpu_load(interval=int(sys.argv[1]),utilization=int(sys.argv[2])):
    cpu_percent = utilization / 100
    load_all_cores(duration_s=interval, target_load=cpu_percent)



#----START OF SCRIPT
if __name__=='__main__':
    print("No of cpu:", multiprocessing.cpu_count())
    generate_cpu_load()