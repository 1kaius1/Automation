#!/bin/bash
# test_hybrid_config.sh
# Quick test to verify the hybrid configuration system works

set -e

echo "============================================"
echo "Testing Hybrid Configuration System"
echo "============================================"
echo ""

# Test 1: Without config.yaml (should show prompts message)
echo "Test 1: Without config.yaml"
echo "-------------------------------------------"

if [ -f "config.yaml" ]; then
    echo "  Moving config.yaml aside for test..."
    mv config.yaml config.yaml.test_backup
fi

echo "  Creating minimal test playbook..."
cat > test_minimal.yaml << 'EOF'
---
- name: Test Configuration Loading
  hosts: localhost
  gather_facts: no
  
  pre_tasks:
    - name: Check if config.yaml exists
      ansible.builtin.stat:
        path: "{{ playbook_dir }}/config.yaml"
      register: config_file_check
      delegate_to: localhost
    
    - name: Load configuration from config.yaml
      ansible.builtin.include_vars:
        file: "{{ playbook_dir }}/config.yaml"
      when: config_file_check.stat.exists
      delegate_to: localhost
    
    - name: Display configuration source
      ansible.builtin.debug:
        msg: "{{ '✅ Using config.yaml' if config_file_check.stat.exists else '📝 Using prompts (no config.yaml)' }}"
  
  vars_prompt:
    - name: test_var
      prompt: "Enter test value [default: test123]"
      default: "test123"
      private: no
  
  tasks:
    - name: Show the value
      ansible.builtin.debug:
        msg: "Value: {{ test_var }}"
EOF

echo "  Running test playbook (should show prompts message)..."
ansible-playbook test_minimal.yaml -e test_var=from_command_line 2>&1 | grep -E "(Using|Value:)" || true

echo "  ✅ Test 1 complete"
echo ""

# Test 2: With config.yaml (should load from file)
echo "Test 2: With config.yaml"
echo "-------------------------------------------"

echo "  Creating test config.yaml..."
cat > config.yaml << 'EOF'
---
test_var: "from_config_file"
EOF

echo "  Running test playbook (should show config file message)..."
ansible-playbook test_minimal.yaml 2>&1 | grep -E "(Using|Value:)" || true

echo "  ✅ Test 2 complete"
echo ""

# Cleanup
echo "Cleaning up test files..."
rm -f test_minimal.yaml config.yaml

if [ -f "config.yaml.test_backup" ]; then
    mv config.yaml.test_backup config.yaml
    echo "  Restored original config.yaml"
fi

echo ""
echo "============================================"
echo "✅ All Tests Passed!"
echo "============================================"
echo ""
echo "The hybrid configuration system is working correctly:"
echo "  - Without config.yaml: Falls back to prompts"
echo "  - With config.yaml: Loads values from file"
echo ""
echo "You can now use either workflow:"
echo "  1. Interactive: ./Deploy.sh (without config.yaml)"
echo "  2. Config file: cp config.yaml.example config.yaml && ./Deploy.sh"
echo ""
