INVENTORY := ansible/inventory.ini

.PHONY: ping facts playbook

# verify connectivity to all hosts
ping:
	ansible all -i $(INVENTORY) -m ping

# gather and display host facts
facts:
	ansible all -i $(INVENTORY) -m setup

# run a playbook: make playbook PLAYBOOK=site.yml
playbook:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)
