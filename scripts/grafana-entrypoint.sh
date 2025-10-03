#!/bin/sh
set -e

echo "🔧 Starting Grafana with environment variable substitution..."

# Substitute environment variables in datasource template
if [ -f "/etc/grafana/provisioning/datasources/datasources.yml.template" ]; then
  sed -e "s/\${DATABASE_NAME}/${DATABASE_NAME}/g" \
      -e "s/\${DATABASE_USER}/${DATABASE_USER}/g" \
      -e "s/\${DATABASE_PASSWORD}/${DATABASE_PASSWORD}/g" \
      /etc/grafana/provisioning/datasources/datasources.yml.template \
      > /etc/grafana/provisioning/datasources/datasources.yml
  echo "✅ Datasource configuration generated with environment variables"

  # Show generated config (with password masked)
  echo "📄 Generated datasource configuration:"
  sed 's/password:.*/password: ********/g' /etc/grafana/provisioning/datasources/datasources.yml
else
  echo "⚠️  Warning: datasources.yml.template not found"
fi

# Verify provisioning directories
echo "📁 Provisioning directory structure:"
ls -la /etc/grafana/provisioning/
echo ""
ls -la /etc/grafana/provisioning/datasources/ || echo "⚠️  datasources directory missing"
ls -la /etc/grafana/provisioning/dashboards/ || echo "⚠️  dashboards directory missing"
echo ""
ls -la /var/lib/grafana/dashboards/ || echo "⚠️  dashboards JSON directory missing"

# Start Grafana
echo "🚀 Starting Grafana server..."
exec /run.sh "$@"
