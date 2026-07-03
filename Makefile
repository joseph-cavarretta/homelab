INVENTORY := ansible/inventory.ini
KUBECONFIG_SRC := /etc/rancher/k3s/k3s.yaml
CONTROL_PLANE := arch-mini

.PHONY: ping facts site playbook kubeconfig argocd root-app argocd-password

# --- provisioning (ansible) ---

# verify connectivity to all hosts
ping:
	ansible all -i $(INVENTORY) -m ping

# gather and display host facts
facts:
	ansible all -i $(INVENTORY) -m setup

# provision the whole cluster: base config + k3s server + agents
site:
	ansible-playbook -i $(INVENTORY) ansible/site.yml

# run an arbitrary playbook: make playbook PLAYBOOK=foo.yml
playbook:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

# copy kubeconfig from the control plane to ~/.kube/config-homelab
kubeconfig:
	ssh $(CONTROL_PLANE) sudo cat $(KUBECONFIG_SRC) \
		| sed 's/127.0.0.1/$(shell ansible-inventory -i $(INVENTORY) --host $(CONTROL_PLANE) | python3 -c "import json,sys; print(json.load(sys.stdin)[\"ansible_host\"])")/' \
		> ~/.kube/config-homelab
	@echo "export KUBECONFIG=~/.kube/config-homelab"

# --- gitops bootstrap (run once; Argo CD owns everything afterwards) ---

argocd:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update argo
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd --create-namespace \
		-f bootstrap/argocd/values.yaml

root-app:
	kubectl apply -f bootstrap/root-app.yaml

argocd-password:
	kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo
