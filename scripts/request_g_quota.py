#!/usr/bin/env python3
"""
Solicita aumento de quota de instâncias G (e VT) On-Demand na AWS.

Quota: "Running On-Demand G and VT Instances" (vCPUs)
Código: L-DB2E81BA | Serviço: ec2

Uso:
    python3 request_g_quota.py <quantidade_vcpus> [--profile PROFILE] [--region REGION]
"""

import argparse
import sys
import boto3
from botocore.exceptions import ClientError

QUOTA_SERVICE_CODE = "ec2"
QUOTA_CODE = "L-DB2E81BA"


def get_current_quota(client):
    response = client.get_service_quota(
        ServiceCode=QUOTA_SERVICE_CODE,
        QuotaCode=QUOTA_CODE,
    )
    return response["Quota"]


def request_quota_increase(client, desired_value):
    response = client.request_service_quota_increase(
        ServiceCode=QUOTA_SERVICE_CODE,
        QuotaCode=QUOTA_CODE,
        DesiredValue=desired_value,
    )
    return response["RequestedQuota"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("vcpus", type=float, help="Nova quantidade de vCPUs desejada")
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--region", default="us-east-1", help="Região AWS (default: us-east-1)")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    client = session.client("service-quotas")

    try:
        current = get_current_quota(client)
        print(f"Quota atual : {current['Value']:.0f} vCPUs")
        print(f"Valor pedido: {args.vcpus:.0f} vCPUs")

        if args.vcpus <= current["Value"]:
            print("Erro: valor solicitado deve ser maior que a quota atual.", file=sys.stderr)
            sys.exit(1)

        req = request_quota_increase(client, args.vcpus)
        print(f"Solicitação criada: {req['Id']}")
        print(f"Status: {req['Status']}")

    except ClientError as e:
        code = e.response["Error"]["Code"]
        message = e.response["Error"]["Message"]
        print(f"Erro AWS [{code}]: {message}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
