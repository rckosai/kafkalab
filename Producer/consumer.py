from confluent_kafka import Consumer, KafkaError

# Config do Kafka
config = {
    'bootstrap.servers': 'localhost:9092', 
    'group.id': 'my-group',
    'auto.offset.reset': 'earliest'
}

# consumidor Kafka
consumer = Consumer(config)

# Tópico para consumir mensagens
topic = 'test_topic'

# Inscreva-se no tópico
consumer.subscribe([topic])

while True:
    msg = consumer.poll(1.0)

    if msg is None:
        continue
    if msg.error():
        if msg.error().code() == KafkaError._PARTITION_EOF:
            continue
        else:
            print('Erro ao receber a mensagem: {}'.format(msg.error()))
    else:
        print('Mensagem recebida: {}'.format(msg.value()))

# Feche o consumidor Kafka ao sair
consumer.close()
