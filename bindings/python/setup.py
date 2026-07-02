"""
Setup script for zigevm Python bindings.
"""

from setuptools import setup, find_packages
import os

# Read README if it exists
readme_path = os.path.join(os.path.dirname(__file__), "README.md")
if os.path.exists(readme_path):
    with open(readme_path, "r", encoding="utf-8") as f:
        long_description = f.read()
else:
    long_description = "Zig EVM Python Bindings"

setup(
    name="zigevm",
    version="0.1.0",
    author="Cryptuon Research",
    author_email="contact@cryptuon.com",
    description="High-performance EVM implementation for L2/Rollup execution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://zig-evm.cryptuon.com/",
    project_urls={
        "Homepage": "https://zig-evm.cryptuon.com/",
        "Documentation": "https://docs.cryptuon.com/zig-evm/",
        "Source": "https://github.com/cryptuon/zig-evm",
    },
    packages=find_packages(),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries",
        "Topic :: System :: Emulators",
    ],
    keywords=["ethereum", "evm", "blockchain", "l2", "rollup", "parallel-execution", "virtual-machine"],
    package_data={
        "zigevm": ["*.so", "*.dylib", "*.dll"],
    },
)
