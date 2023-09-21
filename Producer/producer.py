from confluent_kafka import Producer

# Configurações do Kafka
config = {
    'bootstrap.servers': 'localhost:9092', 
    'client.id': 'python-producer'
}

# Função de callback para manipular a entrega de mensagens
def delivery_report(err, msg):
    if err is not None:
        print('Erro ao entregar a mensagem: {}'.format(err))
    else:
        print('Mensagem entregue com sucesso para o tópico {} [{}]'.format(msg.topic(), msg.partition()))

# produtor Kafka
producer = Producer(config)

# Tópico para enviar mensagens
topic = 'test_topic'

# Nome do arquivo de log interno
log_file = '/var/log/amazon/ssm/errors.log'

# Abra o arquivo de log interno
with open(log_file, 'r') as file:
    for line in file:
        # Envie cada linha do log como mensagem
        producer.produce(topic, value=line.strip(), callback=delivery_report)

# Aguarda entrega das mensagens
producer.flush()
