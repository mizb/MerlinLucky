#!/usr/bin/env python3
# _*_ coding:utf-8 _*_

import os
import sys
import json
import hashlib
from string import Template

parent_path = os.path.dirname(os.path.realpath(__file__))

def md5sum(full_path):
    with open(full_path, 'rb') as rf:
        return hashlib.md5(rf.read()).hexdigest()

def get_or_create():
    conf_path = os.path.join(parent_path, "config.json.js")
    conf = {}
    if not os.path.isfile(conf_path):
        print("config.json.js not found, auto creating...")
        module_name = os.path.basename(parent_path)
        conf["module"] = module_name
        conf["version"] = "0.0.1"
        conf["home_url"] = f"Module_{module_name}.asp"
        conf["title"] = "Lucky"
        conf["description"] = "Lucky 纯轻量 XiaoJV 版"
    else:
        with open(conf_path, "r", encoding="utf-8") as fc:
            conf = json.loads(fc.read())
    return conf

def build_module():
    try:
        conf = get_or_create()
    except Exception as e:
        print(f"config.json.js file format is incorrect: {e}")
        return
    if "module" not in conf:
        print("module is not in config.json.js")
        return
    module_path = os.path.join(parent_path, conf["module"])
    if not os.path.isdir(module_path):
        print(f"not found {module_path} dir, check config.json.js")
        return
    install_path = os.path.join(parent_path, conf["module"], "install.sh")
    if not os.path.isfile(install_path):
        print(f"not found {install_path} file, check install.sh file")
        return
    print("building module...")

    version_file = os.path.join(parent_path, conf["module"], "version")
    with open(version_file, "w", encoding="utf-8") as vf:
        vf.write(conf["version"])
    
    tar_path = os.path.join(parent_path, f"{conf['module']}.tar.gz")
    if os.path.exists(tar_path):
        os.remove(tar_path)
        
    t = Template("cd $parent_path && tar -zcf $module.tar.gz $module")
    os.system(t.substitute({"parent_path": parent_path, "module": conf["module"]}))
    conf["md5"] = md5sum(tar_path)
    
    conf_path = os.path.join(parent_path, "config.json.js")
    with open(conf_path, "w", encoding="utf-8") as fw:
        json.dump(conf, fw, sort_keys=True, indent=4, ensure_ascii=False)
    print("build done:", f"{conf['module']}.tar.gz")

if __name__ == "__main__":
    build_module()
