#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""G3/G4 boot.img 校验器（iQOO 10 / PD2217B）

用法:
  python 20_verify_boot.py boot.img --expect-uname 5.10.246-gki-g02b2e21da816
  python 20_verify_boot.py patched.img --expect-uname 5.10.246-gki-g02b2e21da816 --expect-patched
"""
import sys
import struct
import hashlib
import argparse


def say(*a):
    """GBK 控制台下也能安全打印：遇到编码不了的字符就替换"""
    msg = " ".join(str(x) for x in a)
    try:
        print(msg)
    except UnicodeEncodeError:
        enc = sys.stdout.encoding or "ascii"
        say(msg.encode(enc, "replace").decode(enc, "replace"))

PART_SIZE = 100663296  # 0x6000000


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_header(data):
    if data[:8] != b"ANDROID!":
        return None
    return {
        "kernel_size": struct.unpack_from("<I", data, 0x08)[0],
        "ramdisk_size": struct.unpack_from("<I", data, 0x0C)[0],
        "header_size": struct.unpack_from("<I", data, 0x14)[0],
        "header_ver": struct.unpack_from("<I", data, 0x28)[0],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--expect-uname", required=True, help="手机 uname -r 的值")
    ap.add_argument("--expect-patched", action="store_true", help="这是 KernelSU 补丁镜像")
    a = ap.parse_args()

    fails, warns = [], []
    try:
        data = open(a.image, "rb").read()
    except OSError as e:
        say("[FAIL] 读不到文件: %s" % e)
        return 2

    size = len(data)
    say("文件: %s" % a.image)
    say("大小: {:,} 字节".format(size))
    say("MD5 : %s" % md5_of(a.image))

    # 1. 体积
    if size == PART_SIZE:
        say("[PASS] 体积等于分区大小 {:,}".format(PART_SIZE))
    elif size < PART_SIZE:
        warns.append("体积 {:,} < 分区 {:,}（烧写一般会自动补齐，请确认来源）".format(size, PART_SIZE))
    else:
        fails.append("体积 {:,} 超过分区大小，绝对不能刷".format(size))

    # 2. 头
    hdr = parse_header(data)
    if not hdr:
        fails.append("不是 Android boot 镜像（magic 不是 ANDROID!）")
        hdr = {"kernel_size": 0}
    else:
        say("[INFO] kernel_size={:,} ramdisk_size={:,} header_size={} header_version={}".format(
            hdr["kernel_size"], hdr["ramdisk_size"], hdr["header_size"], hdr["header_ver"]))

    # 3. 内核版本字串
    uname_b = a.expect_uname.encode()
    ksize = hdr.get("kernel_size") or len(data)
    if uname_b in data[:ksize]:
        say("[PASS] 内核版本字串匹配: %s" % a.expect_uname)
    elif uname_b in data:
        warns.append("内核区未找到版本串，但全文件命中（可能内核被压缩）")
    else:
        fails.append("内核版本不匹配！镜像里找不到 %s —— 固件包版本不对，禁止刷入" % a.expect_uname)

    # 4. 补丁特征
    has_ko = b"kernelsu" in data
    if a.expect_patched:
        if has_ko:
            say("[PASS] 检测到 kernelsu 特征（补丁镜像）")
        else:
            fails.append("标称为补丁镜像，但没找到 kernelsu 特征")
    else:
        if has_ko:
            warns.append("原厂镜像里出现 kernelsu 字样？确认文件是否搞混")
        else:
            say("[PASS] 未见 kernelsu 特征（符合原厂）")

    say("-" * 50)
    for w in warns:
        say("[WARN] %s" % w)
    for f in fails:
        say("[FAIL] %s" % f)
    if fails:
        say("[NO] 校验未通过，禁止刷入")
        return 1
    say("[OK] 校验通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
