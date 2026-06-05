import sys
import json
import struct
import math
import os

def read_doubles(path):
    data = []
    with open(path, 'rb') as f:
        b = f.read(8)
        while b:
            data.append(struct.unpack('d', b)[0])
            b = f.read(8)
    return data

def read_ints(path, count):
    arr = []
    with open(path, 'rb') as f:
        b = f.read(4*count)
        if len(b) < 4*count:
            return []
        for i in range(count):
            arr.append(struct.unpack('i', b[i*4:(i+1)*4])[0])
    return arr

def compare_arrays(ref, cand, atol=1e-12, rtol=1e-12):
    if len(ref) != len(cand):
        return {'pass': False, 'reason': 'size mismatch'}
    n = len(ref)
    max_abs = 0.0
    max_rel = 0.0
    sum_sq = 0.0
    for i in range(n):
        a = abs(cand[i] - ref[i])
        max_abs = a if a > max_abs else max_abs
        denom = max(abs(ref[i]), 1e-20)
        rel = a / denom
        max_rel = rel if rel > max_rel else max_rel
        sum_sq += a*a
    rmse = math.sqrt(sum_sq / n) if n>0 else float('nan')
    passed = (max_abs <= atol) or (max_rel <= rtol)
    return {'max_abs_error': max_abs, 'max_rel_error': max_rel, 'rmse': rmse, 'pass': passed}

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: compare_outputs.py <fortran_inputs_dir> <candidate_outputs_dir>')
        sys.exit(2)
    data_dir = sys.argv[1]
    cand_dir = sys.argv[2]
    # read dims
    params = read_ints(os.path.join(data_dir, 'params.bin'), 3)
    if not params:
        print('Cannot read params.bin')
        sys.exit(1)
    nlon, nlat, nlev = params
    size = nlon * nlat * nlev
    files = ['output_tdt.bin','output_teq.bin','output_udt.bin','output_vdt.bin']
    report = {}
    for f in files:
        ref_path = os.path.join(os.path.dirname(data_dir), 'outputs', f)
        cand_path = os.path.join(cand_dir, f)
        if not os.path.exists(ref_path) or not os.path.exists(cand_path):
            report[f] = {'pass': False, 'reason': 'missing file'}
            continue
        ref = read_doubles(ref_path)
        cand = read_doubles(cand_path)
        comp = compare_arrays(ref, cand)
        report[f] = comp
    out = {'files': report}
    os.makedirs('tests/reports', exist_ok=True)
    with open('tests/reports/forcing_module_compare_report.json','w') as of:
        json.dump(out, of, indent=2)
    print(json.dumps(out, indent=2))
